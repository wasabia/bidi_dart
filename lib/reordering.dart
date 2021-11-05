part of bidi_dart;

// import { getBidiCharType, TRAILING_TYPES } from './charTypes.js'
// import { getMirroredCharacter } from './mirroring.js'

/**
 * Given a start and end denoting a single line within a string, and a set of precalculated
 * bidi embedding levels, produce a list of segments whose ordering should be flipped, in sequence.
 * @param {string} string - the full input string
 * @param {GetEmbeddingLevelsResult} embeddingLevelsResult - the result object from getEmbeddingLevels
 * @param {number} [start] - first character in a subset of the full string
 * @param {number} [end] - last character in a subset of the full string
 * @return {number[][]} - the list of start/end segments that should be flipped, in order.
 */
getReorderSegments(string, embeddingLevelsResult, int? start, int? end) {
  var strLen = string.length;


  start = Math.max(0, start == null ? 0 : start);
  end = Math.min(strLen - 1, end == null ? strLen - 1 : end);

  var segments = [];
  embeddingLevelsResult["paragraphs"].forEach((paragraph) {

    int _ps = paragraph["start"];
    int _pe = paragraph["end"];

    var lineStart = Math.max(start!, _ps);
    var lineEnd = Math.min(end!, _pe);
    if (lineStart < lineEnd) {
      // Local slice for mutation
      var _lineLevels = embeddingLevelsResult["levels"].getRange(lineStart, lineEnd + 1).toList();

      Map lineLevels = Map();
      _lineLevels.asMap().forEach((k,v) {
        lineLevels[k] = v;
      });

      // 3.4 L1.4: Reset any sequence of whitespace characters and/or isolate formatting characters at the
      // end of the line to the paragraph level.
      var i = lineEnd;

  
      while ( (i >= lineStart) && ((getBidiCharType(string[i]) & TRAILING_TYPES) != 0) ) {
        i--;

        lineLevels[i] = paragraph["level"];
      }

      // L2. From the highest level found in the text to the lowest odd level on each line, including intermediate levels
      // not actually present in the text, reverse any contiguous sequence of characters that are at that level or higher.
      var maxLevel = paragraph["level"];
      num minOddLevel = double.infinity;

      int lineLevelsLength = lineLevels.keys.reduce((curr, next) => curr > next ? curr: next) + 1;


      for (var i = 0; i < lineLevelsLength; i++) {
        var level = lineLevels[i];
        if (level != null && level > maxLevel) maxLevel = level;
        if (level != null && level < minOddLevel) minOddLevel = level | 1;
      }
      for (var lvl = maxLevel; lvl >= minOddLevel; lvl--) {
        for (var i = 0; i < lineLevelsLength; i++) {
          if (lineLevels[i] >= lvl) {
            var segStart = i;
            while (i + 1 < lineLevelsLength && lineLevels[i + 1] >= lvl) {
              i++;
            }
            if (i > segStart) {
              segments.add([segStart + start, i + start]);
            }
          }
        }
      }
    }
  });
  return segments;
}

/**
 * @param {string} string
 * @param {GetEmbeddingLevelsResult} embedLevelsResult
 * @param {number} [start]
 * @param {number} [end]
 * @return {string} the new string with bidi segments reordered
 */
getReorderedString(string, embedLevelsResult, start, end) {
  var indices = getReorderedIndices(string, embedLevelsResult, start, end);
  var chars = [...string];
  indices.forEach((charIndex, i) => {
    chars[i] = (
      (embedLevelsResult.levels[charIndex] & 1) ? getMirroredCharacter(string[charIndex]) : null
    ) || string[charIndex]
  });
  return chars.join('');
}

/**
 * @param {string} string
 * @param {GetEmbeddingLevelsResult} embedLevelsResult
 * @param {number} [start]
 * @param {number} [end]
 * @return {number[]} an array with character indices in their new bidi order
 */
getReorderedIndices(string, embedLevelsResult, start, end) {
  var segments = getReorderSegments(string, embedLevelsResult, start, end);
  // Fill an array with indices
  var indices = [];
  for (var i = 0; i < string.length; i++) {
    indices[i] = i;
  }
  // Reverse each segment in order
  segments.forEach((element) {
    var start = element[0];
    var end = element[1];
    // [start, end]
    var slice = indices.getRange(start, end + 1).toList();
    var i = slice.length;

    while ( i > 0) {
      i--;
      indices[end - i] = slice[i];
    }
  });
  return indices;
}
