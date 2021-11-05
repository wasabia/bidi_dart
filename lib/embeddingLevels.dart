part of bidi_dart;

// import {
//   BN_LIKE_TYPES,
//   getBidiCharType,
//   ISOLATE_INIT_TYPES,
//   NEUTRAL_ISOLATE_TYPES,
//   STRONG_TYPES,
//   TRAILING_TYPES,
//   TYPES
// } from './charTypes.js'
// import { closingToOpeningBracket, getCanonicalBracket, openingToClosingBracket } from './brackets.js'

// Local type aliases
var TYPE_L = TYPES["L"]!;
var TYPE_R = TYPES["R"]!;
var TYPE_EN = TYPES["EN"]!;
var TYPE_ES = TYPES["ES"]!;
var TYPE_ET = TYPES["ET"]!;
var TYPE_AN = TYPES["AN"]!;
var TYPE_CS = TYPES["CS"]!;
var TYPE_B = TYPES["B"]!;
var TYPE_S = TYPES["S"]!;
var TYPE_ON = TYPES["ON"]!;
var TYPE_BN = TYPES["BN"]!;
var TYPE_NSM = TYPES["NSM"]!;
var TYPE_AL = TYPES["AL"]!;
var TYPE_LRO = TYPES["LRO"]!;
var TYPE_RLO = TYPES["RLO"]!;
var TYPE_LRE = TYPES["LRE"]!;
var TYPE_RLE = TYPES["RLE"]!;
var TYPE_PDF = TYPES["PDF"]!;
var TYPE_LRI = TYPES["LRI"]!;
var TYPE_RLI = TYPES["RLI"]!;
var TYPE_FSI = TYPES["FSI"]!;
var TYPE_PDI = TYPES["PDI"]!;

/**
 * @typedef {object} GetEmbeddingLevelsResult
 * @property {{start, end, level}[]} paragraphs
 * @property {Uint8Array} levels
 */

/**
 * This function applies the Bidirectional Algorithm to a string, returning the resolved embedding levels
 * in a single Uint8Array plus a list of objects holding each paragraph's start and end indices and resolved
 * base embedding level.
 *
 * @param {string} string - The input string
 * @param {"ltr"|"rtl"|"auto"} [baseDirection] - Use "ltr" or "rtl" to force a base paragraph direction,
 *        otherwise a direction will be chosen automatically from each paragraph's contents.
 * @return {GetEmbeddingLevelsResult}
 */
getEmbeddingLevels (string, baseDirection) {
  var MAX_DEPTH = 125;




  // Start by mapping all characters to their unicode type, as a bitmask integer
  var charTypes = new Uint32List(string.length);
  for (var i = 0; i < string.length; i++) {
    charTypes[i] = getBidiCharType(string[i]);
  }

  var charTypeCounts = new Map(); //will be cleared at start of each paragraph
  changeCharType(i, type) {
    var oldType = charTypes[i];
    charTypes[i] = type;
    charTypeCounts[oldType] = charTypeCounts[oldType] - 1;
    if (oldType & NEUTRAL_ISOLATE_TYPES != 0) {
      charTypeCounts[NEUTRAL_ISOLATE_TYPES] = charTypeCounts[NEUTRAL_ISOLATE_TYPES] - 1;
    }
    charTypeCounts[type] = (charTypeCounts[type] ?? 0) + 1;
    if (type & NEUTRAL_ISOLATE_TYPES == 1) {
      charTypeCounts[NEUTRAL_ISOLATE_TYPES] = (charTypeCounts[NEUTRAL_ISOLATE_TYPES] ?? 0) + 1;
    }
  }

  var embedLevels = new Uint8List(string.length);
  var isolationPairs = new Map(); //init->pdi and pdi->init


  indexOfMatchingPDI (isolateStart) {
    // 3.1.2 BD9
    var isolationLevel = 1;
    for (var i = isolateStart + 1; i < string.length; i++) {
      var charType = charTypes[i];
      if (charType & TYPE_B > 0) {
        break;
      }
      if (charType & TYPE_PDI > 0) {
        if (--isolationLevel == 0) {
          return i;
        }
      } else if (charType & ISOLATE_INIT_TYPES > 0) {
        isolationLevel++;
      }
    }
    return -1;
  }

  determineAutoEmbedLevel (start, isFSI) {
    // 3.3.1 P2 - P3
    for (var i = start; i < string.length; i++) {
      var charType = charTypes[i];
      if (charType & (TYPE_R | TYPE_AL) > 0) {
        return 1;
      }
      if ((charType & (TYPE_B | TYPE_L) > 0) || (isFSI && charType == TYPE_PDI)) {
        return 0;
      }
      if (charType & ISOLATE_INIT_TYPES > 0) {
        var pdi = indexOfMatchingPDI(i);
        i = pdi == -1 ? string.length : pdi;
      }
    }
    return 0;
  }

  

  getEmbedDirection (i) {
    return (embedLevels[i] & 1 > 0) ? TYPE_R : TYPE_L;
  }

  // == 3.3.1 The Paragraph Level ==
  // 3.3.1 P1: Split the text into paragraphs
  var paragraphs = []; // [{start, end, level}, ...]
  var paragraph = null;
  for (var i = 0; i < string.length; i++) {
    if (paragraph == null) {
      paragraph = {
        "start": i,
        "end": string.length - 1,
        // 3.3.1 P2-P3: Determine the paragraph level
        "level": baseDirection == 'rtl' ? 1 : baseDirection == 'ltr' ? 0 : determineAutoEmbedLevel(i, false)
      };

      paragraphs.add(paragraph);
    }
    if (charTypes[i] & TYPE_B != 0) {
      paragraph["end"] = i;
      paragraph = null;
    }
  }

  var FORMATTING_TYPES = TYPE_RLE | TYPE_LRE | TYPE_RLO | TYPE_LRO | ISOLATE_INIT_TYPES | TYPE_PDI | TYPE_PDF | TYPE_B;
  var nextEven = (n) {
    return n + ((n & 1) ? 1 : 2);
  };

  var nextOdd = (n) {
    return n + ((n & 1) ? 2 : 1);
  };

  // Everything from here on will operate per paragraph.
  for (var paraIdx = 0; paraIdx < paragraphs.length; paraIdx++) {
    paragraph = paragraphs[paraIdx];
    var statusStack = [{
      "_level": paragraph["level"],
      "_override": 0, //0=neutral, 1=L, 2=R
      "_isolate": 0 //bool
    }];

    var stackTop;
    var overflowIsolateCount = 0;
    var overflowEmbeddingCount = 0;
    var validIsolateCount = 0;
    charTypeCounts.clear();

    // == 3.3.2 Explicit Levels and Directions ==
    for (var i = paragraph["start"]; i <= paragraph["end"]; i++) {
      var charType = charTypes[i];
      stackTop = statusStack[statusStack.length - 1];

      // Set initial counts
      charTypeCounts[charType] = (charTypeCounts[charType] ?? 0) + 1;
      if (charType & NEUTRAL_ISOLATE_TYPES > 0) {
        charTypeCounts[NEUTRAL_ISOLATE_TYPES] = (charTypeCounts[NEUTRAL_ISOLATE_TYPES] ?? 0) + 1;
      }

      // Explicit Embeddings: 3.3.2 X2 - X3
      if (charType & FORMATTING_TYPES > 0) { //prefilter all formatters
        if (charType & (TYPE_RLE | TYPE_LRE) > 0) {
          embedLevels[i] = stackTop._level; // 5.2
          var level = (charType == TYPE_RLE ? nextOdd : nextEven)(stackTop._level);
          if (level <= MAX_DEPTH && overflowIsolateCount == 0 && overflowEmbeddingCount == 0) {
            statusStack.add({
              "_level": level,
              "_override": 0,
              "_isolate": 0
            });
          } else if (overflowIsolateCount == 0) {
            overflowEmbeddingCount++;
          }
        }

        // Explicit Overrides: 3.3.2 X4 - X5
        else if (charType & (TYPE_RLO | TYPE_LRO) > 0) {
          embedLevels[i] = stackTop._level; // 5.2
          var level = (charType == TYPE_RLO ? nextOdd : nextEven)(stackTop._level);
          if (level <= MAX_DEPTH && overflowIsolateCount == 0 && overflowEmbeddingCount == 0) {
            statusStack.add({
              "_level": level,
              "_override": (charType & TYPE_RLO > 0) ? TYPE_R : TYPE_L,
              "_isolate": 0
            });
          } else if (overflowIsolateCount == 0) {
            overflowEmbeddingCount++;
          }
        }

        // Isolates: 3.3.2 X5a - X5c
        else if (charType & ISOLATE_INIT_TYPES > 0) {
          // X5c - FSI becomes either RLI or LRI
          if (charType & TYPE_FSI > 0) {
            charType = determineAutoEmbedLevel(i + 1, true) == 1 ? TYPE_RLI : TYPE_LRI;
          }

          embedLevels[i] = stackTop._level;
          if (stackTop._override) {
            changeCharType(i, stackTop._override);
          }
          var level = (charType == TYPE_RLI ? nextOdd : nextEven)(stackTop._level);
          if (level <= MAX_DEPTH && overflowIsolateCount == 0 && overflowEmbeddingCount == 0) {
            validIsolateCount++;
            statusStack.add({
              "_level": level,
              "_override": 0,
              "_isolate": 1,
              "_isolInitIndex": i
            });
          } else {
            overflowIsolateCount++;
          }
        }

        // Terminating Isolates: 3.3.2 X6a
        else if (charType & TYPE_PDI > 0) {
          if (overflowIsolateCount > 0) {
            overflowIsolateCount--;
          } else if (validIsolateCount > 0) {
            overflowEmbeddingCount = 0;
            while (statusStack[statusStack.length - 1]["_isolate"] == 0) {
              statusStack.removeLast();
            }
            // Add to isolation pairs bidirectional mapping:
            var isolInitIndex = statusStack[statusStack.length - 1]["_isolInitIndex"];
            if (isolInitIndex != null) {
              isolationPairs[isolInitIndex] = i;
              isolationPairs[i] = isolInitIndex;
            }
            statusStack.removeLast();
            validIsolateCount--;
          }
          stackTop = statusStack[statusStack.length - 1];
          embedLevels[i] = stackTop["_level"];
          if (stackTop["_override"] > 0) {
            changeCharType(i, stackTop["_override"]);
          }
        }


        // Terminating Embeddings and Overrides: 3.3.2 X7
        else if (charType & TYPE_PDF > 0) {
          if (overflowIsolateCount == 0) {
            if (overflowEmbeddingCount > 0) {
              overflowEmbeddingCount--;
            } else if (stackTop["_isolate"] == 0 && statusStack.length > 1) {
              statusStack.removeLast();
              stackTop = statusStack[statusStack.length - 1];
            }
          }
          embedLevels[i] = stackTop["_level"]; // 5.2
        }

        // End of Paragraph: 3.3.2 X8
        else if (charType & TYPE_B > 0) {
          embedLevels[i] = paragraph["level"];
        }
      }

      // Non-formatting characters: 3.3.2 X6
      else {
        embedLevels[i] = stackTop["_level"];
        // NOTE: This exclusion of BN seems to go against what section 5.2 says, but is required for test passage
        if (stackTop["_override"] > 0 && charType != TYPE_BN) {
          changeCharType(i, stackTop["_override"]);
        }
      }
    }

    // == 3.3.3 Preparations for Implicit Processing ==

    // Remove all RLE, LRE, RLO, LRO, PDF, and BN characters: 3.3.3 X9
    // Note: Due to section 5.2, we won't remove them, but we'll use the BN_LIKE_TYPES bitset to
    // easily ignore them all from here on out.

    // 3.3.3 X10
    // Compute the set of isolating run sequences as specified by BD13
    var levelRuns = [];
    var currentRun = null;
    var isolationLevel = 0;
    for (var i = paragraph["start"]; i <= paragraph["end"]; i++) {
      var charType = charTypes[i];
      if ((charType & BN_LIKE_TYPES) == 0) {
        var lvl = embedLevels[i];
        var isIsolInit = charType & ISOLATE_INIT_TYPES;
        var isPDI = charType == TYPE_PDI;
        if (isIsolInit > 0) {
          isolationLevel++;
        }
        if (currentRun != null && lvl == currentRun["_level"]) {
          currentRun["_end"] = i;
          currentRun["_endsWithIsolInit"] = isIsolInit;
        } else {
          currentRun = {
            "_start": i,
            "_end": i,
            "_level": lvl,
            "_startsWithPDI": isPDI,
            "_endsWithIsolInit": isIsolInit
          };
          levelRuns.add(currentRun);
        }
        if (isPDI) {
          isolationLevel--;
        }
      }
    }
    var isolatingRunSeqs = []; // [{seqIndices: [], sosType: L|R, eosType: L|R}]
    for (var runIdx = 0; runIdx < levelRuns.length; runIdx++) {
      var run = levelRuns[runIdx];
      if (!run["_startsWithPDI"] || (run["_startsWithPDI"] && isolationPairs[run["_start"]] == null)) {
        var seqRuns = [currentRun = run];
        var pdiIndex;
        while ( currentRun != null && currentRun["_endsWithIsolInit"] != 0 && (pdiIndex = isolationPairs[currentRun._end]) != null) {
          for (var i = runIdx + 1; i < levelRuns.length; i++) {
            if (levelRuns[i]._start == pdiIndex) {
              seqRuns.add(currentRun = levelRuns[i]);
              break;
            }
          }
        }
        // build flat list of indices across all runs:
        var seqIndices = [];
        for (var i = 0; i < seqRuns.length; i++) {
          var run = seqRuns[i];
          for (var j = run["_start"]; j <= run["_end"]; j++) {
            seqIndices.add(j);
          }
        }
        // determine the sos/eos types:
        int firstLevel = embedLevels[seqIndices[0]];
        int prevLevel = paragraph["level"];
        for (var i = seqIndices[0] - 1; i >= 0; i--) {
          if ((charTypes[i] & BN_LIKE_TYPES) == 0) { //5.2
            prevLevel = embedLevels[i];
            break;
          }
        }
        var lastIndex = seqIndices[seqIndices.length - 1];
        int lastLevel = embedLevels[lastIndex];
        int nextLevel = paragraph["level"];
        if ((charTypes[lastIndex] & ISOLATE_INIT_TYPES) == 0) {
          for (var i = lastIndex + 1; i <= paragraph["end"]; i++) {
            if ((charTypes[i] & BN_LIKE_TYPES) == 0) { //5.2
              nextLevel = embedLevels[i];
              break;
            }
          }
        }
        isolatingRunSeqs.add({
          "_seqIndices": seqIndices,
          "_sosType": (Math.max(prevLevel, firstLevel) % 2) == 0 ? TYPE_R : TYPE_L,
          "_eosType": (Math.max(nextLevel, lastLevel) % 2) == 0 ? TYPE_R : TYPE_L
        });
      }
    }

    // The next steps are done per isolating run sequence
    for (var seqIdx = 0; seqIdx < isolatingRunSeqs.length; seqIdx++) {

      var _rsi = isolatingRunSeqs[seqIdx];

      var seqIndices = _rsi["_seqIndices"];
      var sosType = _rsi["_sosType"];
      var eosType = _rsi["_eosType"];

      // == 3.3.4 Resolving Weak Types ==

      // W1 + 5.2. Search backward from each NSM to the first character in the isolating run sequence whose
      // bidirectional type is not BN, and set the NSM to ON if it is an isolate initiator or PDI, and to its
      // type otherwise. If the NSM is the first non-BN character, change the NSM to the type of sos.
      if (charTypeCounts[TYPE_NSM] != null) {
        for (var si = 0; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & TYPE_NSM > 0) {
            var prevType = sosType;
            for (var sj = si - 1; sj >= 0; sj--) {
              if ((charTypes[seqIndices[sj]] & BN_LIKE_TYPES) == 0) { //5.2 scan back to first non-BN
                prevType = charTypes[seqIndices[sj]];
                break;
              }
            }
            changeCharType(i, (prevType & (ISOLATE_INIT_TYPES | TYPE_PDI)) ? TYPE_ON : prevType);
          }
        }
      }

      // W2. Search backward from each instance of a European number until the first strong type (R, L, AL, or sos)
      // is found. If an AL is found, change the type of the European number to Arabic number.
      
      if (charTypeCounts[TYPE_EN] != null && charTypeCounts[TYPE_EN] != 0) {
        for (var si = 0; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & TYPE_EN > 0) {
            for (var sj = si - 1; sj >= -1; sj--) {
              var prevCharType = sj == -1 ? sosType : charTypes[seqIndices[sj]];
              if (prevCharType & STRONG_TYPES == 1) {
                if (prevCharType == TYPE_AL) {
                  changeCharType(i, TYPE_AN);
                }
                break;
              }
            }
          }
        }
      }

      // W3. Change all ALs to R
      if (charTypeCounts[TYPE_AL] != null && charTypeCounts[TYPE_AL] > 0) {
        for (var si = 0; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & TYPE_AL > 0) {
            changeCharType(i, TYPE_R);
          }
        }
      }

      // W4. A single European separator between two European numbers changes to a European number. A single common
      // separator between two numbers of the same type changes to that type.
      if ((charTypeCounts[TYPE_ES] != null && charTypeCounts[TYPE_ES] != 0) || (charTypeCounts[TYPE_CS] != null && charTypeCounts[TYPE_CS] != 0)) {
        for (var si = 1; si < seqIndices.length - 1; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & (TYPE_ES | TYPE_CS) > 0) {
            var prevType = 0, nextType = 0;
            for (var sj = si - 1; sj >= 0; sj--) {
              prevType = charTypes[seqIndices[sj]];
              if ((prevType & BN_LIKE_TYPES) == 0) { //5.2
                break;
              }
            }
            for (var sj = si + 1; sj < seqIndices.length; sj++) {
              nextType = charTypes[seqIndices[sj]];
              if ((nextType & BN_LIKE_TYPES) == 0) { //5.2
                break;
              }
            }
            var _b = (charTypes[i] == TYPE_ES ? prevType == TYPE_EN : (prevType & (TYPE_EN | TYPE_AN)) > 0);
            if (prevType == nextType && _b) {
              changeCharType(i, prevType);
            }
          }
        }
      }

      // W5. A sequence of European terminators adjacent to European numbers changes to all European numbers.
      if (charTypeCounts[TYPE_EN] != null && charTypeCounts[TYPE_EN] != 0) {
        for (var si = 0; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & TYPE_EN > 0) {
            for (var sj = si - 1; sj >= 0 && (charTypes[seqIndices[sj]] & (TYPE_ET | BN_LIKE_TYPES) > 0); sj--) {
              changeCharType(seqIndices[sj], TYPE_EN);
            }
            for (var sj = si + 1; sj < seqIndices.length && (charTypes[seqIndices[sj]] & (TYPE_ET | BN_LIKE_TYPES) > 0); sj++) {
              changeCharType(seqIndices[sj], TYPE_EN);
            }
          }
        }
      }

      // W6. Otherwise, separators and terminators change to Other Neutral.
      var ctc_et = charTypeCounts[TYPE_ET];
      var ctc_es = charTypeCounts[TYPE_ES];
      var ctc_cs = charTypeCounts[TYPE_CS];
      if ((ctc_et != null && ctc_et != 0) || (ctc_es != null && ctc_es != 0) || (ctc_cs != null && ctc_cs != 0)) {
        for (var si = 0; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          if (charTypes[i] & (TYPE_ET | TYPE_ES | TYPE_CS) > 0) {
            changeCharType(i, TYPE_ON);
            // 5.2 transform adjacent BNs too:
            for (var sj = si - 1; sj >= 0 && (charTypes[seqIndices[sj]] & BN_LIKE_TYPES > 0); sj--) {
              changeCharType(seqIndices[sj], TYPE_ON);
            }
            for (var sj = si + 1; sj < seqIndices.length && (charTypes[seqIndices[sj]] & BN_LIKE_TYPES > 0); sj++) {
              changeCharType(seqIndices[sj], TYPE_ON);
            }
          }
        }
      }

      // W7. Search backward from each instance of a European number until the first strong type (R, L, or sos)
      // is found. If an L is found, then change the type of the European number to L.
      // NOTE: implemented in single forward pass for efficiency
      var ctc_en = charTypeCounts[TYPE_EN];
      if (ctc_en != null && ctc_en != 0) {
        for (var si = 0, prevStrongType = sosType; si < seqIndices.length; si++) {
          var i = seqIndices[si];
          var type = charTypes[i];
          if (type & TYPE_EN > 0) {
            if (prevStrongType == TYPE_L) {
              changeCharType(i, TYPE_L);
            }
          } else if (type & STRONG_TYPES > 0) {
            prevStrongType = type;
          }
        }
      }

      // == 3.3.5 Resolving Neutral and Isolate Formatting Types ==

      var ctc_nit = charTypeCounts[NEUTRAL_ISOLATE_TYPES];
      if ( ctc_nit != null && ctc_nit != 0 ) {
        // N0. Process bracket pairs in an isolating run sequence sequentially in the logical order of the text
        // positions of the opening paired brackets using the logic given below. Within this scope, bidirectional
        // types EN and AN are treated as R.
        var R_TYPES_FOR_N_STEPS = (TYPE_R | TYPE_EN | TYPE_AN);
        var STRONG_TYPES_FOR_N_STEPS = R_TYPES_FOR_N_STEPS | TYPE_L;

        // * Identify the bracket pairs in the current isolating run sequence according to BD16.
        var bracketPairs = [];
        {
          var openerStack = [];
          for (var si = 0; si < seqIndices.length; si++) {
            // NOTE: for any potential bracket character we also test that it still carries a NI
            // type, as that may have been changed earlier. This doesn't seem to be explicitly
            // called out in the spec, but is required for passage of certain tests.
            if (charTypes[seqIndices[si]] & NEUTRAL_ISOLATE_TYPES > 0) {
              var char = string[seqIndices[si]];
              var oppositeBracket;
              // Opening bracket
              if (openingToClosingBracket(char) != null) {
                if (openerStack.length < 63) {
                  openerStack.add({ "char": char, "seqIndex": si });
                } else {
                  break;
                }
              }
              // Closing bracket
              else if ((oppositeBracket = closingToOpeningBracket(char)) != null) {
                for (var stackIdx = openerStack.length - 1; stackIdx >= 0; stackIdx--) {
                  var stackChar = openerStack[stackIdx].char;
                  if (stackChar == oppositeBracket ||
                    stackChar == closingToOpeningBracket(getCanonicalBracket(char)) ||
                    openingToClosingBracket(getCanonicalBracket(stackChar)) == char
                  ) {
                    bracketPairs.add([openerStack[stackIdx].seqIndex, si]);
                    openerStack.length = stackIdx; //removeLast the matching bracket and all following
                    break;
                  }
                }
              }
            }
          }
          bracketPairs.sort((a, b) => a[0] - b[0]);
        }
        // * For each bracket-pair element in the list of pairs of text positions
        for (var pairIdx = 0; pairIdx < bracketPairs.length; pairIdx++) {
          var _bpi = bracketPairs[pairIdx];
          var openSeqIdx = _bpi[0];
          var closeSeqIdx = _bpi[1];
          // a. Inspect the bidirectional types of the characters enclosed within the bracket pair.
          // b. If any strong type (either L or R) matching the embedding direction is found, set the type for both
          // brackets in the pair to match the embedding direction.
          var foundStrongType = false;
          var useStrongType = 0;
          for (var si = openSeqIdx + 1; si < closeSeqIdx; si++) {
            var i = seqIndices[si];
            if (charTypes[i] & STRONG_TYPES_FOR_N_STEPS > 0) {
              foundStrongType = true;
              var lr = (charTypes[i] & R_TYPES_FOR_N_STEPS > 0) ? TYPE_R : TYPE_L;
              if (lr == getEmbedDirection(i)) {
                useStrongType = lr;
                break;
              }
            }
          }
          // c. Otherwise, if there is a strong type it must be opposite the embedding direction. Therefore, test
          // for an established context with a preceding strong type by checking backwards before the opening paired
          // bracket until the first strong type (L, R, or sos) is found.
          //    1. If the preceding strong type is also opposite the embedding direction, context is established, so
          //    set the type for both brackets in the pair to that direction.
          //    2. Otherwise set the type for both brackets in the pair to the embedding direction.
          if (foundStrongType && useStrongType == 0) {
            useStrongType = sosType;
            for (var si = openSeqIdx - 1; si >= 0; si--) {
              var i = seqIndices[si];
              if (charTypes[i] & STRONG_TYPES_FOR_N_STEPS > 0) {
                var lr = (charTypes[i] & R_TYPES_FOR_N_STEPS > 0) ? TYPE_R : TYPE_L;
                if (lr != getEmbedDirection(i)) {
                  useStrongType = lr;
                } else {
                  useStrongType = getEmbedDirection(i);
                }
                break;
              }
            }
          }
          if (useStrongType > 0) {
            charTypes[seqIndices[openSeqIdx]] = charTypes[seqIndices[closeSeqIdx]] = useStrongType;
            // * Any number of characters that had original bidirectional character type NSM prior to the application
            // of W1 that immediately follow a paired bracket which changed to L or R under N0 should change to match
            // the type of their preceding bracket.
            if (useStrongType != getEmbedDirection(seqIndices[openSeqIdx])) {
              for (var si = openSeqIdx + 1; si < seqIndices.length; si++) {
                if ((charTypes[seqIndices[si]] & BN_LIKE_TYPES) == 0) {
                  if (getBidiCharType(string[seqIndices[si]]) & TYPE_NSM) {
                    charTypes[seqIndices[si]] = useStrongType;
                  }
                  break;
                }
              }
            }
            if (useStrongType != getEmbedDirection(seqIndices[closeSeqIdx])) {
              for (var si = closeSeqIdx + 1; si < seqIndices.length; si++) {
                if ((charTypes[seqIndices[si]] & BN_LIKE_TYPES) == 0) {
                  if (getBidiCharType(string[seqIndices[si]]) & TYPE_NSM) {
                    charTypes[seqIndices[si]] = useStrongType;
                  }
                  break;
                }
              }
            }
          }
        }

        // N1. A sequence of NIs takes the direction of the surrounding strong text if the text on both sides has the
        // same direction.
        // N2. Any remaining NIs take the embedding direction.
        for (var si = 0; si < seqIndices.length; si++) {
          if (charTypes[seqIndices[si]] & NEUTRAL_ISOLATE_TYPES > 0) {
            var niRunStart = si, niRunEnd = si;
            var prevType = sosType; //si == 0 ? sosType : (charTypes[seqIndices[si - 1]] & R_TYPES_FOR_N_STEPS) ? TYPE_R : TYPE_L
            for (var si2 = si - 1; si2 >= 0; si2--) {
              if (charTypes[seqIndices[si2]] & BN_LIKE_TYPES > 0) {
                niRunStart = si2; //5.2 treat BNs adjacent to NIs as NIs
              } else {
                prevType = (charTypes[seqIndices[si2]] & R_TYPES_FOR_N_STEPS > 0) ? TYPE_R : TYPE_L;
                break;
              }
            }
            var nextType = eosType;
            for (var si2 = si + 1; si2 < seqIndices.length; si2++) {
              if (charTypes[seqIndices[si2]] & (NEUTRAL_ISOLATE_TYPES | BN_LIKE_TYPES) > 0) {
                niRunEnd = si2;
              } else {
                nextType = (charTypes[seqIndices[si2]] & R_TYPES_FOR_N_STEPS > 0) ? TYPE_R : TYPE_L;
                break;
              }
            }
            for (var sj = niRunStart; sj <= niRunEnd; sj++) {
              charTypes[seqIndices[sj]] = prevType == nextType ? prevType : getEmbedDirection(seqIndices[sj]);
            }
            si = niRunEnd;
          }
        }
      }
    }

    // == 3.3.6 Resolving Implicit Levels ==

    for (var i = paragraph["start"]; i <= paragraph["end"]; i++) {
      var level = embedLevels[i];
      var type = charTypes[i];
      // I2. For all characters with an odd (right-to-left) embedding level, those of type L, EN or AN go up one level.
      if (level & 1 > 0) {
        if (type & (TYPE_L | TYPE_EN | TYPE_AN) > 0) {
          embedLevels[i]++;
        }
      }
        // I1. For all characters with an even (left-to-right) embedding level, those of type R go up one level
      // and those of type AN or EN go up two levels.
      else {
        if (type & TYPE_R > 0) {
          embedLevels[i]++;
        } else if (type & (TYPE_AN | TYPE_EN) > 0) {
          embedLevels[i] += 2;
        }
      }

      // 5.2: Resolve any LRE, RLE, LRO, RLO, PDF, or BN to the level of the preceding character if there is one,
      // and otherwise to the base level.
      if (type & BN_LIKE_TYPES > 0) {
        embedLevels[i] = i == 0 ? paragraph["level"] : embedLevels[i - 1];
      }

      // 3.4 L1.1-4: Reset the embedding level of segment/paragraph separators, and any sequence of whitespace or
      // isolate formatting characters preceding them or the end of the paragraph, to the paragraph level.
      // NOTE: this will also need to be applied to each individual line ending after line wrapping occurs.
      if (i == paragraph["end"] || (getBidiCharType(string[i]) & (TYPE_S | TYPE_B)) != 0) {
        var j = i;

        while (j >= 0 && (getBidiCharType(string[j]) & TRAILING_TYPES) > 0) {
          j--;
          embedLevels[j] = paragraph["level"];
        }
      }
    }
  }



  // DONE! The resolved levels can then be used, after line wrapping, to flip runs of characters
  // according to section 3.4 Reordering Resolved Levels
  return {
    "levels": embedLevels,
    "paragraphs": paragraphs
  };

}
