// Web-Sync: Tables Plugin
// WebSync uses RequireJS for modules.
// define( [pluginName], [requiredModules], definition);
// pluginName is an optional argument that should only be used if the module is being bundled/loaded without RequireJS. It should match the path it's being required as.
define('/assets/tables.js',['edit','websync'],function(edit,websync){ var self = {};
    // Save all variables and information to the self object.

    // Plugins should use a jQuery namespace for ease of use.
	// Bind Example: $(document).bind("click.Tables", clickHandler);
	// Unbind Example: $("*").unbind(".Tables");
    $("#Insert").append($('<button id="table" title="Table" class="btn Table"><i class="icon-table"></i></button>'))
    $("#table").bind("click.Tables",function(e){
        console.log(e);
        var new_table = $("<table><tbody><tr><td></td><td></td></tr><tr><td></td><td></td></tr></tbody></table>")
        WebSync.insertAtCursor(new_table)
    });
    $(".content_well").delegate("table","click.Tables",function(e){
        if(self.selectedElem.contentEditable!="true"){
            $('a:contains("Table")').click();
        }
        e.stopPropagation();
    });
    $(".page").bind("click.Tables",function(e){
        console.log(e);
        self.clearSelect();
    });
    $(".content_well").delegate("td","click.Tables",function(e){
        console.log(e);
        console.log(this);
        if(this!=self.selectedElem){
            self.cursorSelect(this);
        }
    });
    $(".content_well").delegate("td","contextmenu.Tables",function(e){
        if(this!=self.selectedElem){
            self.cursorSelect(this);
        }
        if(self.selectedElem.contentEditable!="true"){
            e.preventDefault();
            $(this).contextmenu();
        }
    });
    $(".content_well").delegate("td","dblclick.Tables",function(e){
        self.selectedEditable(true);
    });
    $(".content_well").bind("keydown.Tables",function(e){
        if(self.selectedElem){
            if(self.selected==true&&!e.shiftKey){
                var editting = false;
                if(self.selectedElem.contentEditable){
                    editting=self.selectedElem.contedEditable=="true";
                }
                if(e.keyCode==13){
                    self.cursorMove(0,1);
                } else if(e.keyCode==27){
                    // Escape
                    self.selectedEditable(false);
                } else if(e.keyCode==37&&!editting){
                    // Left arrow
                    self.cursorMove(-1,0);
                    e.preventDefault();
                }else if(e.keyCode==39&&!editting){
                    // Right arrow
                    self.cursorMove(1,0);
                    e.preventDefault();
                }else if(e.keyCode==38&&!editting){
                    // Up arrow
                    self.cursorMove(0,-1);
                    e.preventDefault();
                }else if(e.keyCode==40&&!editting){
                    // Down arrow
                    self.cursorMove(0,1);
                    e.preventDefault();
                } else {
                    if(!self.selectedElem.contentEditable||self.selectedElem.contentEditable=="false"){
                        self.selectedEditable(true);

                        $(self.selectedElem).focus();
                        //WebSync.setCaretPosition(self.selectedElem,0);
                    }
                    setTimeout(self.cursorUpdate,1);
                }
            } else {
                if(!self.selectedElem.contentEditable||self.selectedElem.contentEditable=="false"){
                    self.selectedEditable(true);

                    $(self.selectedElem).focus();
                    //WebSync.setCaretPosition(self.selectedElem,0);
                }
                setTimeout(self.cursorUpdate,1);
            }
        }
    });
    $(".ribbon").append($('<div id="Table" class="Table container">Table Editting</div>'));
    $(document.body).append($('<div id="table_cursor" class="Table"></div><div id="tablemenu"><ul class="dropdown-menu" role="menu"><li><a tabindex="-1" href="#"><i class="icon-plus"></i>Insert Column</a></li><li><a tabindex="-1" href="#"><i class="icon-trash"></i>Delete Column</a></li><li><a tabindex="-1" href="#"><i class="icon-plus"></i>Insert Row</a></li><li><a tabindex="-1" href="#"><i class="icon-trash"></i>Delete Row</a></li><li class="divider"></li><li><a tabindex="-1" href="#"><i class="icon-pencil"></i>Customize Cell</a></li></ul></div>'));
    $("td").attr("data-target","#tablemenu");
    $("#tablemenu a").bind("click.Tables",function(e){
        e.preventDefault();
    });
    $('#tablemenu a:contains("Insert Column")').bind("click.Tables",function(e){
    });
    $('#tablemenu a:contains("Delete Column")').bind("click.Tables",function(e){
    });
    $('#tablemenu a:contains("Insert Row")').bind("click.Tables",function(e){
    });
    $('#tablemenu a:contains("Delete Row")').bind("click.Tables",function(e){
    });
    WebSync.updateRibbon();
	// Function: void [plugin=edit].disable();
    // Disables the plugin. This has to be set for possible plugin unloading.
	self.disable = function(){
		var elem = $(".Table").remove();
		WebSync.updateRibbon();
		$("*").unbind(".Tables");
		$("*").undelegate(".Tables");
	}
	// Helper methods:
	self.cursorSelect = function(td){
		// Cleanup last elem.
		if(self.selectedElem){
			self.selectedEditable(false);
		}
		document.getSelection().empty();
		self.selected = true;
		self.selectedElem = td;
		self.selectedEditable(false);
		self.cursorUpdate();
	}
	self.cursorMove = function(dColumn, dRow){
		self.selectedEditable(false);
		var pos = self.selectedPos();
		var column = pos[0];
		var row = pos[1];
		if(self.selectedElem.parentElement.parentElement.children.length>row+dRow&&self.selectedElem.parentElement.parentElement.children[0].children.length>column+dColumn&&row+dRow>=0&&column+dColumn>=0){
			var new_td = self.selectedElem.parentElement.parentElement.children[row+dRow].children[column+dColumn];
			self.cursorSelect(new_td);
		}

	}
	self.cursorUpdate = function(){
		var pos = $(self.selectedElem).position();
		$("#table_cursor").offset(pos).height($(self.selectedElem).height()).width($(self.selectedElem).width()).get(0).scrollIntoViewIfNeeded();
	}
	self.selectedEditable = function(edit){
		if(!edit){
			self.selectedElem.contentEditable=null;
			$("#table_cursor").css({borderStyle: 'solid', outlineStyle: 'solid'});
			$('a:contains("Table")').click();
		}else{
			self.selectedElem.contentEditable=true;
			$("#table_cursor").css({borderStyle: 'dashed', outlineStyle: 'dashed'});
			$('a:contains("Text")').click();
			WebSync.setEndOfContenteditable(self.selectedElem);
		}
	}
    self.clearSelect = function(){
		if(self.selected){
			self.selected = false;
			self.selectedEditable(false);
			$("#table_cursor").offset({left:-10000});
			delete self.selectedElem;
			$('a:contains("Text")').click();
		}
	}
	self.selectedPos = function(){
		var child = self.selectedElem;
		var column = 0;
		while( (child = child.previousSibling) != null )
			column++;
		child = self.selectedElem.parentElement
		var row = 0
		while( (child = child.previousSibling) != null )
			row++;
		return [column,row];
	}
	self.tableSize = function(){
		return [self.selectedElem.parentElement.children.length,self.selectedElem.parentElement.parentElement.children.length]
	}

    // Return self so other modules can hook into this one.
    return self;
});
