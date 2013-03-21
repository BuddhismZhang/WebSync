importScripts('/js/diff_match_patch.js');


self.addEventListener('message', function(e) {
    var data = e.data;
    if(data.cmd=='diff'){
        var new_html = data.newHtml;
        var old_html = data.oldHtml;
        var diffsHTML = diff_htmlMode(old_html,new_html);
		var patchesHTML = dmp.patch_make(diffsHTML);
		var patch_textHTML = dmp.patch_toText(patchesHTML);
        self.postMessage({cmd:'patched',patch: patch_textHTML);
    }
}, false);
diff_htmlMode = function (text1,text2){
		var a = WebSync.dmp.diff_htmlToChars_(text1,text2);
		var lineText1 = a.chars1;
		var lineText2 = a.chars2;
		var lineArray = a.lineArray;
		var diffs = WebSync.dmp.diff_main(lineText1,lineText2, false);
		WebSync.dmp.diff_charsToHTML_(diffs, lineArray);
		return diffs;
}
// Create a diff after replacing all HTML tags with unicode characters.
diff_match_patch.prototype.diff_htmlToChars_ = function(text1, text2){
	var lineArray = [];  // e.g. lineArray[4] == 'Hello\n'
	var lineHash = {};   // e.g. lineHash['Hello\n'] == 4

	// '\x00' is a valid character, but various debuggers don't like it.
	// So we'll insert a junk entry to avoid generating a null character.
	lineArray[0] = '';

	/**
	* Split a text into an array of strings.  Reduce the texts to a string of
	* hashes where each Unicode character represents one line.
	* Modifies linearray and linehash through being a closure.
	* @param {string} text String to encode.
	* @return {string} Encoded string.
	* @private
	*/
	function diff_linesToCharsMunge_(text) {
		var chars = ""+text;
		// Walk the text, pulling out a substring for each line.
		// text.split('\n') would would temporarily double our memory footprint.
		// Modifying text would create many large strings to garbage collect.
		var lineStart = 0;
		var lineEnd = -1;
		// Keeping our own length variable is faster than looking it up.
		var lineArrayLength = lineArray.length;
		while (lineEnd < text.length - 1) {
			var prevLineEnd = lineEnd;
			if(prevLineEnd==-1){
				prevLineEnd=0;
			}
			lineStart = text.indexOf('<',lineEnd);
			lineEnd = text.indexOf('>', lineStart);
			if (lineEnd == -1) {
				lineEnd = text.length - 1;
			}
			var line = text.substring(lineStart, lineEnd + 1);
			lineStart = lineEnd + 1;

			if (lineHash.hasOwnProperty ? lineHash.hasOwnProperty(line) :
				(lineHash[line] !== undefined)) {
				chars = chars.replace(line,String.fromCharCode(lineHash[line]));
			} else {
				chars = chars.replace(line,String.fromCharCode(lineArrayLength));
				lineHash[line] = lineArrayLength;
				lineArray[lineArrayLength++] = line;
			}
		}
		return chars;
	}

	var chars1 = diff_linesToCharsMunge_(text1);
	var chars2 = diff_linesToCharsMunge_(text2);
	return {chars1: chars1, chars2: chars2, lineArray: lineArray};
}
diff_match_patch.prototype.diff_charsToHTML_ = function(diffs, lineArray) {
  for (var x = 0; x < diffs.length; x++) {
    var chars = diffs[x][1];
    var text = ""+chars;
    for (var y = 0; y < lineArray.length; y++) {
        var chara = String.fromCharCode(y);
        while(text.indexOf(chara)!=-1){
            var n_text=text.replace(chara,lineArray[y]);
            text=n_text;
        }
    }
    diffs[x][1] = text;
  }
};

