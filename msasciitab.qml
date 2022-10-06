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

    // Total offset to be added to the current line's write pointer due to the additional width added
    // by barlines, extra spacing etc.
    property var barIdxOffset: 0

    // Represents the next upcoming barline boundary
    property var barIdxTotal: 0

    // ASCII tab content
    property var textContent: ""

    // Maximum width, in characters, of a single line of tablature (excluding legends and barlines)
    property var maxLineWidth: 112

    // Total width, in characters, to be assigned to each quarter note/crotchet beat
    property var quarterNoteWidth: 12

    FileIO {
        id: asciiTabWriter
        source: filePath
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
            var fileName = this.fileUrl.toString().replace("file://", "").replace(/^\/(.:\/)(.*)$/, "$1$2");
            
            console.log("fileUrl: " + this.fileUrl);
            console.log("fileName: " + fileName);

            // Generate ASCII, then write to file
            processTab();
            writeTab(fileName);
        }
        onRejected: {
            console.log("Cancelled; quitting");
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
        console.log("Musescore version: " + mscoreMajorVersion + "." + mscoreMinorVersion + "." + mscoreUpdateVersion);
        
        if ((mscoreMajorVersion < 3) || (mscoreMinorVersion < 3)) {
            console.log("Incompatible version; Musescore 3.3 and above is required to run this plugin");      
            errorDialog.openErrorDialog("Incompatible version; Musescore 3.3 and above is required to run this plugin");
        }
        else if (typeof curScore === 'undefined') {  
            // requiresScore: true should handle this 
            console.log("No score");      
            errorDialog.openErrorDialog("No score");
        }
        else {
            console.log("filePath: " + filePath);
            console.log("curScore.scoreName: " + curScore.scoreName);      
            directorySelectDialog.open();
        }      
    }

    function writeTab(fileName) {

        // Write to file
        asciiTabWriter.source = fileName;
        console.log("Writing to: " + fileName);
        asciiTabWriter.write(textContent);   

        // Done; quit
        console.log("Done");
        Qt.quit();
    }
    
    function processTab() {

        // Initialise tab line buffer
        var tabBuf = [[], [], [], [], [], []]; 

        // Create and reset cursor
        var cursor = curScore.newCursor();
        cursor.voice = 0
        cursor.staffIdx = 0;       
        cursor.rewind(0);

        var barNum = 0;          // Current bar number
        var lineLengthLimit = 0; // Score index where line should be wrapped next 
       
        while (cursor.segment) { 
            
            var curTick = cursor.segment.tick;
            var nextTick = cursor.segment.next.tick;

            // Each quarter note consists of 480 ticks
            var curCharIdx = (cursor.segment.tick * quarterNoteWidth) / 480;
            var nextCharIdx = (cursor.segment.next.tick * quarterNoteWidth) / 480; 

            var barIdxWidth = (cursor.measure.timesigNominal.ticks * quarterNoteWidth) / 480; 

            console.log(" ");
            console.log("Bar: " + barNum); 
            console.log("Current/next tick: " + curTick + "/" + nextTick); 
            console.log("Current/next character index: " + curCharIdx + "/" + nextCharIdx); 

            // Check if a new bar has been reached
            if (curCharIdx >= barIdxTotal) { 
                barNum++;  
                barIdxTotal += barIdxWidth;
                            
                console.log("New bar! (#" + barNum + ")");

                if (barIdxTotal >= lineLengthLimit) {
                    if (barNum > 1) {
                        // Add final barline before break
                        barlineTabBuf(tabBuf, barIdxOffset + barIdxTotal);

                        // Flush tab buffer
                        flushTabBuf(tabBuf);
                    }

                    // Add new string legend
                    legendTabBuf(tabBuf, 0)

                    lineLengthLimit += maxLineWidth;
                }

                // Add new barline and extra padding
                barlineTabBuf(tabBuf, barIdxOffset + curCharIdx);
                extendTabBuf(tabBuf, barIdxOffset + curCharIdx + 1, barIdxOffset + curCharIdx + 4);
                barIdxOffset += 4;      
            }

            // Debug stuff
            //console.log("________________________________________");
            //console.log("Bar " + barNum);
            var timeSig = cursor.measure.timesigNominal;
            //console.log("Current time signature: " + timeSig.numerator + "/" + timeSig.denominator);
            //console.log("Indices " + curCharIdx + " - " + nextCharIdx);
            //console.log("barIdxTotal: " + barIdxTotal + ", lineLengthLimit: " + lineLengthLimit);

            // Write notes/rests
            if (cursor.element && cursor.element.type == Element.CHORD) {             
                // Get chord
                var curChord = cursor.element;

                extendTabBuf(tabBuf, barIdxOffset + curCharIdx, barIdxOffset + nextCharIdx);

                // Get per-chord annotations
                //var chordAnnotation = getChordElementAnnotation(curTick, nextTick);
                //console.log("chordAnnotation: " + chordAnnotation);
                
                // Fill out string buffer for current segment 
                // -128 = no note
                // -1 = ghost note
                var stringBuf = [-128, -128, -128, -128, -128, -128];

                for (var i=0; i<curChord.notes.length; i++) {                   
                    // Check that note is first in a tied group of notes, if it is tied at all;
                    // if the note is tied from a previous note, we don't need to write it again
                    if (curChord.notes[i].firstTiedNote.position.ticks != curChord.notes[i].position.ticks)
                        continue;

                    var stringNum = curChord.notes[i].string;
                    var fretNum = curChord.notes[i].fret; 
                    var symOffset = (fretNum > 9) ? 2 : 1;

                    // Look for modified noteheads
                    if (curChord.notes[i].ghost) // ghost note
                        stringBuf[stringNum] = -1;
                    else // regular ol' note
                        stringBuf[stringNum] = fretNum;

                    // Look for elements attached to note (bends, parentheses etc.)
                    var noteElements = curChord.notes[i].elements;
                    if (noteElements.length > 0) {
                        for (var j=0; j<noteElements.length; j++) {
                            switch (noteElements[j].name) {               
                                case "Bend":
                                    tabBuf[stringNum][barIdxOffset + curCharIdx + symOffset] = "b";
                                    break;

                                case "Symbol":
                                    //console.log("Symbol SymId: " + noteElements[j].symbol);
                                    if (noteElements[j].symbol == SymId.noteheadParenthesisLeft)
                                        tabBuf[stringNum][barIdxOffset + curCharIdx - 1] = "(";
                                    else if (noteElements[j].symbol == SymId.noteheadParenthesisRight)
                                        tabBuf[stringNum][barIdxOffset + curCharIdx + symOffset] = ")";
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

                // Write notes for current segment
                addNotesToTabBuf(tabBuf, stringBuf, barIdxOffset + curCharIdx);        
            }
            else if (cursor.element && cursor.element.type == Element.REST) {
                extendTabBuf(tabBuf, barIdxOffset + curCharIdx, barIdxOffset + nextCharIdx);       
            }
            
            cursor.next();    
        }

        // Final barline
        barlineTabBuf(tabBuf, barIdxOffset + barIdxTotal);

        // Render final part of tab to textContent
        flushTabBuf(tabBuf);
    }

    function getChordElementAnnotation(startTick, endTick) {

        var startStaff = 0;
        var endStaff = curScore.nstaves;

        //curScore.selection.clear();
        // This doesn't seem to be working currently
        var ret = curScore.selection.selectRange(startTick, endTick, startStaff, endStaff);
        console.log("selectRange: " + ret);

        var chordElementsList = curScore.selection.elements;
        var annotation = "-";

        console.log(chordElementsList.length + " elements in segment " + curScore.selection.startSegment.tick + " to " + curScore.selection.endSegment.tick);
        for (var i=0; i<chordElementsList.length; i++) {
            console.log("Element " + i);
            switch (chordElementsList[i].name) {
                case "Articulation":
                    console.log("Articulation: " + chordElementsList[i].name);
                    console.log("SymId: " + chordElementsList[i].symbol);
                    annotation = getArticulationAnnotation(chordElementsList[i]);
                    break;
                case "ChordLine":
                    console.log("ChordLine: " + chordElementsList[i].name);
                    console.log("SymId: " + chordElementsList[i].symbol);
                    annotation = "/"; // TODO: properly handle different ChordLine types
                    break;
                default:
                    console.log("Other element type: " + chordElementsList[i].name);
                    break;
            }
        } 

        return annotation;      
    }

    function getArticulationAnnotation(articulationElement) {

        switch (articulationElement.symbol) {
            case SymId.articStaccatoAbove:
            case SymId.articStaccatoBelow:
            case SymId.articAccentStaccatoAbove:
            case SymId.articAccentStaccatoBelow:
            case SymId.articTenutoStaccatoAbove:
            case SymId.articTenutoStaccatoBelow:
            case SymId.articMarcatoStaccatoAbove:
            case SymId.articMarcatoStaccatoBelow:    
                return ".";
            case SymId.articStaccatissimoAbove:
            case SymId.articStaccatissimoBelow:
            case SymId.articStaccatissimoStrokeAbove:
            case SymId.articStaccatissimoStrokeBelow:
            case SymId.articStaccatissimoWedgeAbove:
            case SymId.articStaccatissimoWedgeBelow:
                return "'";
            default:
                return "-";
        }
    }

    // Write note numbers/note heads into tabBuf at charIdx
    function addNotesToTabBuf(tabBuf, stringBuf, charIdx) {

        var tabBufNumStrings = tabBuf.length;

        for (var line=0; line<tabBufNumStrings; line++) { 
            if (stringBuf[line] > 9) {
                tabBuf[line][charIdx] = String(Math.floor(stringBuf[line] / 10));
                tabBuf[line][charIdx+1] = String(stringBuf[line] % 10);     
            } 
            else if (stringBuf[line] >= 0) {
                tabBuf[line][charIdx] = String(stringBuf[line]);
            }
            else if (stringBuf[line] == -1) { // ghost note
                tabBuf[line][charIdx] = "x";    
            } 
        }
    }

    // Write more empty space into tabBuf
    function extendTabBuf(tabBuf, startCharIdx, endCharIdx) {

        var tabBufNumStrings = tabBuf.length;

        for (var line=0; line<tabBufNumStrings; line++)
            for (var idx=startCharIdx; idx<endCharIdx; idx++)
                tabBuf[line][idx] = "-";
    }

    // Write a new (single) barline into tabBuf
    function barlineTabBuf(tabBuf, idx) {

        var tabBufNumStrings = tabBuf.length;

        for (var line=0; line<tabBufNumStrings; line++)
            tabBuf[line][idx] = "|";
        
        barIdxOffset++;
    }

    // Write the string legend which appears at the start of each line of tablature into tabBuf
    function legendTabBuf(tabBuf, idx) {

        tabBuf[0][idx] = "e";
        tabBuf[1][idx] = "B";
        tabBuf[2][idx] = "G";
        tabBuf[3][idx] = "D";
        tabBuf[4][idx] = "A";
        tabBuf[5][idx] = "E";

        barIdxOffset++;
    }

    // Clear tabBuf, writing its contents to the text output
    function flushTabBuf(tabBuf) {

        var tabBufLen = tabBuf[0].length;
        var tabBufNumStrings = tabBuf.length;

        for (var line=0; line<tabBufNumStrings; line++) { 
            textContent += tabBuf[line].join("");
            textContent += "\r\n";             
        }  
        textContent += "\r\n"; 

        // Clear tab buffer
        for (var line=0; line<tabBufNumStrings; line++)
            tabBuf[line].length = 0;
    }
}
