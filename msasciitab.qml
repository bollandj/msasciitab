import QtQuick 2.9
import QtQuick.Controls 2.2
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
    version: "0.2"
    requiresScore: true

    // Total number of extra characters' width added by barlines etc.
    property var writeOffset: 0

    // Represents the next upcoming barline boundary
    property var barIdxTotal: 0

    // ASCII tab content
    property var textContent: ""

    // Maximum width of a single line of tab in characters (excludes legends/barlines)
    property var maxLineWidth: 112

    FileIO {
        id: asciiTabWriter
        onError: console.log(msg + "\nFilename = " + asciiTabWriter.source);
    }

    FileDialog {
        id: directorySelectDialog
        title: qsTr("Export ASCII tab...")
        selectFolder: false
        nameFilters: ["ASCII tab files (*.tab)", "Text files (*.txt)"]
        selectExisting: false
        selectMultiple: false
        visible: false
        onAccepted: {
            var fname = this.fileUrl.toString().replace("file://", "").replace(/^\/(.:\/)(.*)$/, "$1$2");
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
            console.log("Path: " + filePath);
            console.log("Filename: " + curScore.scoreName + ".mscz");
            directorySelectDialog.open();
        }      
    }

    function writeTab(fname) {
        // Generate ASCII tab
        processTab();

        // Write to file
        asciiTabWriter.source = fname;
        console.log("Writing to: " + fname);
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

        // Score index where line should be wrapped next 
        var lineLengthLimit = 0;
       
        while (cursor.segment) { 
            // Each quarter note consists of 480 ticks
            // This corresponds to a width of 12 characters in the generated ASCII tab
            var curIdx = cursor.segment.tick/40;
            var nextIdx = cursor.segment.next.tick/40; 
            var barWidth = cursor.measure.timesigNominal.ticks/40;  

            // Check if a new bar has been reached
            if (curIdx >= barIdxTotal) { 
                barNum++;  
                barIdxTotal += barWidth;
                            
                console.log("New bar! (#" + barNum + ")");

                if (barIdxTotal >= lineLengthLimit) {
                    if (barNum > 1) {
                        // Add final barline before break
                        barlineTabBuf(tabBuf, writeOffset + barIdxTotal);

                        // Flush tab buffer
                        flushTabBuf(tabBuf);
                    }

                    // Add new string legend
                    legendTabBuf(tabBuf, 0)

                    lineLengthLimit += maxLineWidth;
                }

                // Add new barline and extra padding
                barlineTabBuf(tabBuf, writeOffset + curIdx);
                extendTabBuf(tabBuf, writeOffset + curIdx + 1, writeOffset + curIdx + 4);
                writeOffset += 4;      
            }

            // Debug stuff
            console.log("________________________________________");
            console.log("Bar " + barNum);
            var timeSig = cursor.measure.timesigNominal;
            console.log("Current time signature: " + timeSig.numerator + "/" + timeSig.denominator);
            console.log("Indices " + curIdx + " - " + nextIdx);
            console.log("barIdxTotal: " + barIdxTotal + ", lineLengthLimit: " + lineLengthLimit);

            // Write notes/rests
            if (cursor.element && cursor.element.type == Element.CHORD) {             
                // Get chord
                var curChord = cursor.element;

                extendTabBuf(tabBuf, writeOffset + curIdx, writeOffset + nextIdx);
                
                // Fill out string buffer for current segment 
                // -128 = no note
                var stringBuf = [-128, -128, -128, -128, -128, -128];
                for (var i=0; i<curChord.notes.length; i++) {
                    var stringNum = curChord.notes[i].string;
                    var fretNum = curChord.notes[i].fret; 
                    var symOffset = (fretNum > 9) ? 2 : 1;

                    // Check that note is first in a tied group of notes, if it is tied at all
                    if (curChord.notes[i].firstTiedNote.position.ticks == curChord.notes[i].position.ticks)
                    {
                        // Look for modified noteheads
                        if (curChord.notes[i].ghost) // ghost note
                            stringBuf[stringNum] = -1;
                        else // regular ol' note
                            stringBuf[stringNum] = fretNum;

                        // Look for elements attached to note (bends, parentheses etc.)
                        var noteElements =  curChord.notes[i].elements;
                        if (noteElements.length > 0) {
                            for (var j=0; j<noteElements.length; j++) {
                                switch (noteElements[j].name) {               
                                    case "Bend":
                                        tabBuf[stringNum][writeOffset + curIdx + symOffset] = "b";
                                        break;

                                    case "Symbol":
                                        console.log("symId: " + noteElements[j].symbol);
                                        if (noteElements[j].symbol == SymId.noteheadParenthesisLeft)
                                            tabBuf[stringNum][writeOffset + curIdx - 1] = "(";
                                        else if (noteElements[j].symbol == SymId.noteheadParenthesisRight)
                                            tabBuf[stringNum][writeOffset + curIdx + symOffset] = ")";
                                        else
                                            console.log("Unknown symbol type!")      
                                        break;

                                    default:
                                        console.log("Another type of note-attached element!")       
                                        break;
                                }
                            }
                        }  
                    }   
                }

                // Write notes for current segment
                addNotesToTabBuf(tabBuf, stringBuf, writeOffset + curIdx);        
            }
            else if (cursor.element && cursor.element.type == Element.REST) {
                extendTabBuf(tabBuf, writeOffset + curIdx, writeOffset + nextIdx);       
            }
            
            cursor.next();    
        }

        // Final barline
        barlineTabBuf(tabBuf, writeOffset + barIdxTotal);

        // Render final part of tab to textContent
        flushTabBuf(tabBuf);

        console.log("________________________________________");
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
            else if (stringBuf[line] == -1) { // ghost note
                tabBuf[line][curIdx] = "x";    
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
            textContent += "\r\n";             
        }  
        textContent += "\r\n"; 

        // Clear tab buffer
        for (var line=0; line<6; line++)
            tabBuf[line].length = 0;
    }
}
