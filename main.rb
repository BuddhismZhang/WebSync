# It was the night before Christmas and all through the house, not a creature was coding: UTF-8, not even with a mouse.
require 'bundler'
require 'tempfile'
require 'digest/md5'
Bundler.require(:default)
require 'sinatra/sprockets-helpers'
require 'sinatra/asset_pipeline'


# Monkey patched Redis for easy caching.
class Redis
  def cache(key, expire=nil)
    if (value = get(key)).nil?
      value = yield(self)
      set(key, value)
      expire(key, expire) if expire
      value
    else
      value
    end
  end
end
# Ease of use connection to the redis server.
$redis = Redis.new :driver=>:hiredis
DataMapper.setup(:default, "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/main.db")
# Redis has issues with datamapper associations especially Many-to-many.
#$adapter = DataMapper.setup(:default, {:adapter => "redis"});
#$redis = $adapter.redis

Sinatra::Sprockets = Sprockets


class Document
    include DataMapper::Resource
    property :id, Serial
    property :name, String
    property :body, Text
    property :created, DateTime
    property :last_edit_time, DateTime
    property :public, Boolean, :default=>false
    property :config, Object, :default=>{}
    has n, :assets, :through => Resource
    belongs_to :user
    def config_set key, value
        n_config = config.dup
        n_config[key]=value
        self.config= n_config
    end
end
# Assets could be javascript or css
class Asset
    include DataMapper::Resource
    property :id, Serial
    property :name, String
    property :description, String
    property :url, String
    property :type, Discriminator
    has n, :documents, :through => Resource
end
class Javascript < Asset; end
class Stylesheet < Asset; end
class User
    include DataMapper::Resource
    property :email, String, :key=>true
    property :password, BCryptHash
    has n, :documents
    property :config, Object, :default=>{}
    def config_set key, value
        n_config = config.dup
        n_config[key]=value
        self.config= n_config
    end
end
DataMapper.finalize
DataMapper.auto_upgrade!
class WebSync < Sinatra::Base
    use Rack::Logger
    helpers do
        def logger
            request.logger
        end
        def current_user
            if logged_in?
                return User.get(session['user'])
            end
            nil
        end
        def logged_in?
            (!session['userhash'].nil?)&&$redis.get('userhash:'+session['userhash'])==session['user']
        end
        def login_required
            if !logged_in?
                redirect "/login?#{env["REQUEST_PATH"]}"
            end
        end
        def register email, pass
            email.downcase!
            if User.get(email).nil?
                user = User.create({:email=>email,:password=>pass})
                authenticate email, pass
                return user
            elsif authenticate email, pass
                return current_user
            end
            nil
        end
        def authenticate email, pass, expire=nil
            email.downcase!
            user = User.get(email)
            if user.nil?
                return false
            end
            if user.password==pass
                session_key = SecureRandom.uuid
                $redis.set("userhash:#{session_key}",email)
                session['userhash']=session_key
                session['user']=email
                if !expire.nil?
                    $redis.expire("userhash:#{session_key}",expire)
                end
                return true
            end
            false
        end
        def logout
            $redis.del "userhash:#{session['userhash']}"
            session['userhash']=nil
            session['user']=nil
        end
        def render_login_button
            if logged_in?
               return '<a href="/logout" title="Sign Out"><i class="icon-signout icon-large"></i> Sign Out</a>'
            else
               return '<a href="/login" title="Sign In"><i class="icon-signin icon-large"></i> Sign In</a>'
            end
        end
    end

    configure :development do
        Bundler.require(:development)
        use PryRescue::Rack
    end

    configure :production do
        Bundler.require(:production)
        set :assets_css_compressor, :sass
        set :assets_js_compressor, :closure
        set :assets_precompile, %w(bundle.css bundle-norm.js bundle-edit.js *.png *.favico *.jpg *.svg *.eot *.ttf *.woff)
        set :assets_precompile_no_digest, %w(*.js)
    end
    configure do
        enable :sessions
        set :session_secret, "Web-Sync sdkjfskadfh1h3248c99sj2j4j2343"
        set :server, 'thin'
        set :sockets, []
        set :template_engine, :erb
        register Sinatra::AssetPipeline
        sprockets.append_path File.join(root, 'assets', 'stylesheets')
        sprockets.append_path File.join(root, 'assets', 'javascripts')
        sprockets.append_path File.join(root, 'assets', 'images')
    end
    $dmp = DiffMatchPatch.new

    $table = Javascript.first_or_create(:name=>'Tables',:description=>'Table editing support',:url=>'/assets/tables.js')
    $chat = Javascript.first_or_create(:name=>'Chat',:description=>'Talk with other users!',:url=>'/assets/chat.js')
    get '/login' do
        if !logged_in?
            erb :login
        else
            redirect '/'
        end
    end
    post '/login' do
        redirect_loc = '/'
        if params[:redirect]!=''
            redirect_loc = params[:redirect]
        end
        if authenticate params[:email],params[:password]
            redirect redirect_loc
        else
            redirect "/login?#{redirect_loc}"
        end
    end
    get '/register' do
        redirect '/login'
    end
    post '/register' do
        if register params[:email],params[:password]
            redirect '/'
        else
            redirect '/login'
        end
    end
    get '/logout' do
        if logged_in?
            logout
        end
        redirect '/login'
    end
    not_found do
        erb :not_found
    end
    #get '/assets/*.css' do
    #    content_type 'text/css'
    #    assets_environment[params[:splat][0]+'.css'].to_s
    #end
    #get '/assets/*.js' do
    #    content_type 'text/javascript'
    #    assets_environment[params[:splat][0]+'.js'].to_s
    #end

    get '/' do
        #$redis.cache("index",300) do
            @javascripts = []
            erb :index
        #end
    end
    get '/documentation' do
        erb :documentation
    end
    get '/new' do
        login_required
        doc = Document.create(
            :name => 'Unnamed Document',
            :body => '',
            :created => Time.now,
            :last_edit_time => Time.now,
            :user => current_user
        )
        doc.assets << Asset.get(1)
        doc.assets << Asset.get(2)
        doc.save
        redirect "/#{doc.id.base62_encode}/edit"
    end
    get '/upload' do
        login_required
        erb :upload
    end
    post '/upload' do
        tempfile = params[:file][:tempfile]
        filename = params[:file][:filename]
        filetype = params[:file][:type]
        content = nil
        # TODO: Split upload/download into its own external server. Right now Unoconv is blocking.
        `unoconv -f html #{tempfile.path}`
        exit_status = $?.to_i
        if exit_status == 0
            content = File.read(tempfile.path+".html")
        else
            if filetype=="application/pdf"
                content = PDFToHTMLR::PdfFilePath.new(tempfile.path).convert.force_encoding("UTF-8")
            elsif filetype=='text/html'
                content = File.read(tempfile.path)
            elsif filename.split('.').pop=='docx'
                    # This pretty much just reads plain text...
                    content = Docx::Document.open(tempfile.path).to_html.force_encoding("UTF-8")
            else
                logger.info "Unoconv failed and Unrecognized filetype: #{params[:file][:type]}"
            end
        end
        if content!=nil
            doc = Document.create(
                :name => filename,
                :body => content,
                :created => Time.now,
                :last_edit_time => Time.now,
                :user => current_user
            )
            doc.assets << Asset.get(1)
            doc.save
            redirect "/#{doc.id.base62_encode}/edit"
        else
            redirect "/"
        end
    end
    get '/:doc/download/:format' do
        if !%w(bib doc doc6 doc95 docbook html odt ott ooxml pdb pdf psw rtf latex sdw sdw4 sdw3 stw sxw text txt vor vor4 vor3 xhtml bmp emf eps gif jpg met odd otg pbm pct pgm png ppm ras std svg svm swf sxd sxd3 sxd5 tiff wmf xpm odg odp pot ppt pwp sda sdd sdd3 sdd4 sti stp sxi vor5 csv dbf dif ods pts pxl sdc sdc4 sdc3 slk stc sxc xls xls5 xls95 xlt xlt5).include?(params[:format])
            redirect '/'
        end
        login_required
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if (!doc.public)&&doc.user!=current_user
            redirect '/'
        end
        file = Tempfile.new('websync-export')
        file.write doc.body
        file.close
        `unoconv -f #{params[:format]} #{file.path}`
        if $?.to_i==0
            export_file = file.path+"."+params[:format]
            response.headers['content_type'] = `file --mime -b export_file`.split(';')[0]
            attachment(doc.name+'.'+params[:format])
            response.write(File.read(export_file))
        else
            redirect '/'
        end
        file.unlink
    end
=begin
    get '/:doc/download/docx' do
        login_required
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if (!doc.public)&&doc.user!=current_user
            redirect '/'
        end
        response.headers['content_type'] = "application/octet-stream"
        attachment(doc.name+'.docx')
        response.write(doc.body)
        #send_data doc.body, :filename=>doc.name+".docx"
    end
    # TODO: Switch PDF generation to a dedicated server w/ xorg-server
    # Requires wkhtmltopdf
    get '/:doc/download/pdf' do
        login_required
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if (!doc.public)&&doc.user!=current_user
            redirect '/'
        end
        response.headers['content_type'] = "application/pdf"
        kit = PDFKit.new(doc.body, :page_size => 'Letter')
        attachment(doc.name+'.pdf')
        response.write(kit.to_pdf)
    end
    get '/:doc/download/html' do
        login_required
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if (!doc.public)&&doc.user!=current_user
            redirect '/'
        end
        response.headers['content_type'] = "text/html"
        attachment(doc.name+'.html')
        response.write(doc.body)
    end
=end
    get '/:doc/delete' do
        login_required
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if doc.user==current_user
            doc.destroy!
        end
        redirect '/'
    end
    get '/:doc/edit' do
        doc_id = params[:doc].base62_decode
        doc = Document.get doc_id
        if doc.nil?
            redirect 'notfound'
        end
        if !request.websocket?
            login_required
            if (!doc.public)&&doc.user!=current_user
                redirect '/'
            end
            @javascripts = [
                #'/assets/bundle-edit.js'
            ]
            @doc = doc
            if !@doc.nil?
                @client_id = $redis.incr("clientid").base62_encode
                @client_key = SecureRandom.uuid
                $redis.set "websocket:id:#{@client_id}",current_user.email
                $redis.set "websocket:key:#{@client_id}", @client_key
                $redis.expire "websocket:id:#{@client_id}", 60*60*24*7
                $redis.expire "websocket:key:#{@client_id}", 60*60*24*7
                @no_menu = true
                erb :edit
            else
                redirect '/'
            end
        # Websocket edit
        else
            #TODO: Authentication for websockets
            redis_sock = EM::Hiredis.connect.pubsub
            redis_sock.subscribe("doc:#{doc_id.base62_encode}")
            authenticated = false
            user = nil
            client_id = nil
            request.websocket do |ws|
                websock = ws
                ws.onopen do
                    warn "websocket open"
                end
                ws.onmessage do |msg|
                    data = JSON.parse(msg.force_encoding("UTF-8"));
                    puts "JSON: #{data.to_s}"
                    if data['type']=='auth'
                        if $redis.get("websocket:key:#{data['id']}") == data['key']
                            # Extend key expiry time
                            email = $redis.get "websocket:id:#{data['id']}"
                            user = User.get(email)
                            if (!doc.public)&&doc.user!=user
                                redis_sock.close_connection
                                ws.close_connection
                                return
                            end
                            authenticated = true
                            client_id = data['id']
                            $redis.expire "websocket:id:#{client_id}", 60*60*24*7
                            $redis.expire "websocket:key:#{client_id}", 60*60*24*7
                            user_prop = "doc:#{doc_id.base62_encode}:users"
                            user_raw = $redis.get(user_prop)
                            if !user_raw.nil?
                                users = JSON.parse(user_raw)
                            else
                                users = {}
                            end
                            user_id = Digest::MD5.hexdigest(email.strip.downcase)
                            users[client_id]={id:user_id,email:email.strip}
                            $redis.set user_prop,JSON.dump(users)
                            $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:JSON.dump({type:"new_user",id:client_id,user:{id:user_id,email:email.strip}})})
                            ws.send JSON.dump({type:'info',user_id:user_id,users:users})
                            puts "[Websocket Client Authed] ID: #{client_id}, Email: #{email}"
                        else
                            ws.close_connection
                        end
                    end
                    if authenticated
                        # This replaces all the text w/ the provided content.
                        if data["type"]=="text_update"
                            doc.body = data["text"]
                            doc.last_edit_time = Time.now
                            if !doc.save
                                puts("Save errors: #{doc.errors.inspect}")
                            end
                            $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:msg})
                        # Google Diff-Match-Patch algorithm
                        elsif data['type']=='text_patch'
                            doc = Document.get doc_id
                            #I'm pretty sure this works just fine. The main issue seems to be diffing w/ structure content. We'll see with time.
                            #html_optimized_patches = diff_htmlToChars_ doc.body, URI::decode(data['patch'])
                            #puts html_optimized_patches.inspect
                            patches = $dmp.patch_from_text data['patch']
                            doc.body = $dmp.patch_apply(patches,doc.body)[0]
                            doc.last_edit_time = Time.now
                            if !doc.save
                                puts("Save errors: #{doc.errors.inspect}")
                            end
                            $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:msg})
                        # Sets the name
                        elsif data['type']=="name_update"
                            doc.name = data["name"]
                            doc.last_edit_time = Time.now
                            if !doc.save
                                puts("Save errors: #{doc.errors.inspect}")
                            end
                            $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:msg})
                        # Loads scripts
                        elsif data['type']=="load_scripts"
                            msg = {type:'scripts', js:[],css:[]}
                            doc.assets.each do |asset|
                                arr = :js;
                                if asset.type=="javascript"
                                    arr = :js
                                elsif asset.type=="stylesheet"
                                    arr = :css
                                end
                                msg[arr].push asset.url
                            end
                            ws.send JSON.dump msg
                        elsif data['type']=='connection'
                        elsif data['type']=='config'
                            if data['action']=='set'
                                if data['property']=='public'
                                    doc.public = data['value']
                                    doc.save
                                else
                                    if data['space']=='user'
                                            user.config_set data['property'],data['value']
                                            user.save
                                    elsif data['space']=='document'
                                            doc.config_set data['property'],data['value']
                                            doc.save
                                    end
                                end
                            elsif data['action']=='get'
                                if data['property']=='public'
                                    ws.send JSON.dump({type: 'config',action: 'get', property:'public', value: doc.public})
                                else
                                    if data['space']=='user'
                                            ws.send JSON.dump({type: 'config', action: data['action'], space: data['space'], property: data['property'], value: user.config[data['property']],id:data['id']})
                                    elsif data['space']=='document'
                                            ws.send JSON.dump({type: 'config', action: data['action'], space: data['space'], property: data['property'], value: doc.config[data['property']],id:data['id']})
                                    end
                                end
                            end
                        elsif data['type']=='client_event'
                            $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:JSON.dump({type:"client_event",event:data['event'],from:client_id,data:data['data']})})
                        end
                    end
                end
                ws.onclose do
                    warn("websocket closed")
                    redis_sock.close_connection
                    if authenticated
                        user_prop = "doc:#{doc_id.base62_encode}:users"
                        users = JSON.parse($redis.get(user_prop))
                        users.delete client_id
                        $redis.set user_prop,JSON.dump(users)
                        $redis.publish "doc:#{doc_id.base62_encode}", JSON.dump({type:"client_bounce",client:client_id,data:JSON.dump({type:"exit_user",id:client_id})})
                    end
                end
                redis_sock.on(:message) do |channel, message|
                    puts "[#{client_id}]#{channel}: #{message}"
                    data = JSON.parse(message)
                    if data['client']!=client_id
                        if data['type']=="client_bounce"
                            ws.send data['data']
                        end
                    end
                end
            end
        end
    end

=begin
# This might be completely useless since it seems like you only have to structure for diff.
# Create a diff after replacing all HTML tags with unicode characters.
def diff_htmlToChars_ text1, text2
    lineArray = []  # e.g. lineArray[4] == 'Hello\n'
    lineHash = {}   # e.g. lineHash['Hello\n'] == 4

    # '\x00' is a valid character, but various debuggers don't like it.
    # So we'll insert a junk entry to avoid generating a null character.
    lineArray[0] = ''

    #/**
    #* Split a text into an array of strings.  Reduce the texts to a string of
    #* hashes where each Unicode character represents one line.
    #* Modifies linearray and linehash through being a closure.
    #* @param {string} text String to encode.
    #* @return {string} Encoded string.
    #* @private
    #*/
    def diff_linesToCharsMunge_ text, lineArray, lineHash
        chars = ""+text
        #// Walk the text, pulling out a substring for each line.
        #// text.split('\n') would would temporarily double our memory footprint.
        #// Modifying text would create many large strings to garbage collect.
        lineStart = 0
        lineEnd = 0
        #// Keeping our own length variable is faster than looking it up.
        lineArrayLength = lineArray.length;
        while lineEnd <(text.length - 1)
            prevLineEnd = lineEnd
            if prevLineEnd==nil
                prevLineEnd=0
            end
            lineStart = text.index('<',lineEnd)
            if lineStart.nil?
                lineEnd=nil
                break
            else
                lineEnd = text.index('>', lineStart)
            end
            if lineEnd.nil?
                lineEnd = text.length - 1
            end
            line = text[lineStart..lineEnd]
            lineStart = lineEnd + 1

            if lineHash.has_key? line
                chars.gsub!(line,[lineHash[line]].pack("U"))
            else
                chars.gsub!(line,[lineArrayLength].pack("U"))
                lineHash[line] = lineArrayLength
                lineArray[lineArrayLength] = line
                lineArrayLength +=1
            end
        end
        return chars;
    end

    chars1 = diff_linesToCharsMunge_(text1, lineArray,lineHash)
    chars2 = diff_linesToCharsMunge_(text2,lineArray,lineHash)
    return {chars1: chars1, chars2: chars2, lineArray: lineArray}
end
def diff_charsToHTML_ diffs, lineArray
  (0..(diffs.length-1)).each do |x|
    chars = diffs[x][1];
    text = ""+chars
    (0..(lineArray-1)).each do |y|
      text.gsub!([y].pack("U"),lineArray[y])
    end
    diffs[x][1] = text;
  end
end
=end
end
