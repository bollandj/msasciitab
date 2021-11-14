import QtQuick 2.2
import QtQuick.Controls 1.1
import QtQuick.Layouts 1.1
import QtQuick.Dialogs 1.2
import Qt.labs.settings 1.0
import Qt.labs.folderlistmodel 2.1
import QtQml 2.2

import MuseScore 3.0
import FileIO 3.0

MuseScore {
    menuPath: "Plugins.ASCII Tab Exporter.Export ASCII tab"
    description: "Generates an ASCII tab"
    version: "0.0.1"
    requiresScore: true

    // Total number of extra characters' width added by barlines etc.
    property var writeOffset: 0

    // Represents the next upcoming barline boundary
    property var barIdxTotal: 0

    // ASCII tab content
    property var textContent: ""

    // Maximum width of a single line of tab in characters
    property var maxLineWidth: 112

    FileIO {
        id: asciiTabWriter
        onError: console.log(msg + "\nFilename = " + asciiTabWriter.source);
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
        processTab();
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

        // Create and reset cursor
        var cursor = curScore.newCursor();
        cursor.voice = 0
        cursor.staffIdx = 0;       
        cursor.rewind(0);

        // Current bar number
        var barNum = 0;
        
        // Add string legend
        legendTabBuf(tabBuf, 0)

        // Add extra barline
        barlineTabBuf(tabBuf, 1);
       
        while (cursor.segment) { 
            // Each quarter note consists of 480 ticks
            // This corresponds to a width of 12 characters in the generated ASCII tab
            var curIdx = cursor.segment.tick/40;
            var nextIdx = cursor.segment.next.tick/40; 
            var barWidth = cursor.measure.timesigNominal.ticks/40;  

            console.log("________________________________________");
            var timeSig = cursor.measure.timesigNominal;
            console.log("Current time signature: " + timeSig.numerator + "/" + timeSig.denominator);
            console.log("Indices " + curIdx + " - " + nextIdx);

            // Check if a new bar has been reached
            if (curIdx >= barIdxTotal) {
                barIdxTotal += barWidth;
                console.log("New bar! (#" + barNum++ + ")");

                // Add new barline and extra padding
                barlineTabBuf(tabBuf, writeOffset + curIdx);
                extendTabBuf(tabBuf, writeOffset + curIdx + 1, writeOffset + curIdx + 4);
                writeOffset += 4;
            }

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

                extendTabBuf(tabBuf, writeOffset + curIdx, writeOffset + nextIdx);

                // Write notes for current segment
                addNotesToTabBuf(tabBuf, stringBuf, writeOffset + curIdx);        
            }
            else if (cursor.element && cursor.element.type == Element.REST) {
                extendTabBuf(tabBuf, writeOffset + curIdx, writeOffset + nextIdx);       
            } 
            
            cursor.next();    

            // End of bar
            //barlineTabBuf(tabBuf, idx);
        }

        // Barline to end
        barlineTabBuf(tabBuf, writeOffset + barIdxTotal);

        // Render tab to textContent
        flushTabBuf(tabBuf);

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

        //writeOffset += endIdx - startIdx;
    }

    function barlineTabBuf(tabBuf, idx) {
        for (var line=0; line<6; line++)
            tabBuf[line][idx] = "|";
        
        writeOffset++;
    }

    function legendTabBuf(tabBuf, idx) {
        tabBuf[0][idx] = "e";
        tabBuf[1][idx] = "B";
        tabBuf[2][idx] = "G";
        tabBuf[3][idx] = "D";
        tabBuf[4][idx] = "A";
        tabBuf[5][idx] = "E";

        writeOffset++;
    }

    function flushTabBuf(tabBuf) {
        var tabBufLen = tabBuf[0].length;

        for (var line=0; line<6; line++) { 
            textContent += tabBuf[line].join("");
            textContent += "\n";             
        }  
        textContent += "\n"; 

        //writeOffset = -barIdxTotal; 
    }
}
