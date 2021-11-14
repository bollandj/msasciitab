import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Layouts 1.1
import QtQuick.Dialogs 1.2
import Qt.labs.settings 1.0
// FileDialog
import Qt.labs.folderlistmodel 2.1
import QtQml 2.2

import MuseScore 3.0
import FileIO 3.0

MuseScore {
    menuPath: "Plugins.ASCII Tab Exporter.Export ASCII tab"
    description: "Generates an ASCII tab"
    version: "0.0.1"
    requiresScore: true

    property var helloWorld: "Hello World!"

    FileIO {
        id: asciiTabWriter
        onError: console.log(msg + "\nFilename = " + asciiTabWriter.source)
    }

    FileDialog {
		id: directorySelectDialog
		title: qsTr("Export ASCII tab...")
		selectFolder: true
		visible: false
		onAccepted: {
            var fname = this.folder.toString().replace("file://", "").replace(/^\/(.:\/)(.*)$/, "$1$2");
            writeTab(fname);
        }
        onRejected: {
            console.log("Cancelled");
            Qt.quit();
        }
		Component.onCompleted: visible = false
	}

    MessageDialog {
		id: errorDialog
		visible: false
		title: "Error"
		text: "Error"
		onAccepted: {
			Qt.quit();
		}
		function openErrorDialog(message) {
			text = message;
			open();
		}
	}

    onRun: {
        if (typeof curScore === 'undefined') {   
            console.log("No score");      
            errorDialog.openErrorDialog("No score");
        }
        else {
            console.log("Start");   
            directorySelectDialog.folder = ((Qt.platform.os=="windows")? "file:///" : "file://") + curScore.filePath;
            directorySelectDialog.open();
        }      
    }

    function writeTab(fname) {
        // Generate ASCII tab
        var textContent = processTab();
        var name = curScore.metaTag("workTitle");
        console.log("Name: " + name);

        // Write to file
        asciiTabWriter.source = fname + "/test.tab";
        console.log("Writing to: " + asciiTabWriter.source);
        asciiTabWriter.write(textContent);   

        // Done; quit
        console.log("Done");
        Qt.quit();
    }
    
    function processTab() {
        // Initialise tab line buffer and text output
        var tabBuf = [[], [], [], [], [], []]; 
        var textContent = "";

        // Not used currently
        var startStaff = 0;
        var endStaff = curScore.nstaves;
        var startTick = 0;
        var endTick = curScore.lastSegment.tick + 1;

        // Create and reset cursor
        var cursor = curScore.newCursor();
        cursor.voice = 0
        cursor.staffIdx = 0;       
        cursor.rewind(0);

        var offset = 0;

        while (cursor.segment) { 
            // 
            var curIdx = cursor.segment.tick/40;
            var nextIdx = cursor.segment.next.tick/40; 
            var timeSig = cursor.measure.timesigNominal.ticks/40;  

            console.log("*******************");
            console.log("Indices " + curIdx*40 + " - " + nextIdx*40);

            var timeSig = cursor.measure.timesigNominal;
            console.log("Time signature: " + timeSig.numerator + "/" + timeSig.denominator);
            console.log("(" + timeSig.ticks/40 + " indices per bar)");
   
            console.log("Measure " + cursor.measure);

            if (cursor.element && cursor.element.type == Element.CHORD) {             
                // Get chord
                var curChord = cursor.element;
                
                // Fill out string buffer for current segment (-1 = no note)
                var stringBuf = [-1, -1, -1, -1, -1, -1];
                for (var i=0; i<curChord.notes.length; i++) {
                    var stringNum = curChord.notes[i].string;
                    var fretNum = curChord.notes[i].fret;
                    stringBuf[stringNum] = fretNum;
                }

                // Extend tab buffer
                extendTabBuf(tabBuf, curIdx, nextIdx);

                // Write notes for current segment
                addNotesToTabBuf(tabBuf, stringBuf, curIdx);        
            }
            else if (cursor.element && cursor.element.type == Element.REST) {
                // Extend tab buffer
                extendTabBuf(tabBuf, curIdx, nextIdx);       
            } 
            
            cursor.next();    

            // End of bar
            //barlineTabBuf(tabBuf, idx);
        }

        // Render tab to textContent
        textContent = flushTabBuf(textContent, tabBuf);

        return textContent;
    }

    function addNotesToTabBuf(tabBuf, stringBuf, curIdx) {
        for (var line=0; line<6; line++) { 
            if (stringBuf[line] > 9) {
                tabBuf[line][curIdx] = String(Math.floor(stringBuf[line] / 10));
                tabBuf[line][curIdx+1] = String(stringBuf[line] % 10);     
            } 
            else if (stringBuf[line] >= 0) {
                tabBuf[line][curIdx] = String(stringBuf[line]);
            }
        }
    }

    function extendTabBuf(tabBuf, startIdx, endIdx) {
        for (var line=0; line<6; line++)
            for (var idx=startIdx; idx<endIdx; idx++)
                tabBuf[line][idx] = "-";
    }

    function barlineTabBuf(tabBuf, idx) {
        for (var line=0; line<6; line++)
            tabBuf[line][idx] = "|";
    }

    function flushTabBuf(textContent, tabBuf) {
        var tabBufLen = tabBuf[0].length;

        for (var line=0; line<6; line++) { 
            textContent += tabBuf[line].join("");
            textContent += "\n";             
        }  
        textContent += "\n"; 

        return textContent;  
    }

    function legendTabBuf(tabBuf, idx) {
        tabBuf[0][idx] = "e";
        tabBuf[1][idx] = "B";
        tabBuf[2][idx] = "G";
        tabBuf[3][idx] = "D";
        tabBuf[4][idx] = "A";
        tabBuf[5][idx] = "E";
    }
}
