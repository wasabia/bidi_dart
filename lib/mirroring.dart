part of bidi_dart;

// import data from './data/bidiMirroring.data.js'
// import { parseCharacterMap } from './util/parseCharacterMap.js'

var mirrorMap;

parse () {
  if (mirrorMap == null) {
    //const start = performance.now()
    var _pcm = parseCharacterMap(mirrorData, true);
    Map<dynamic, dynamic> map = _pcm["map"];
    Map<dynamic, dynamic> reverseMap = _pcm["reverseMap"];
 
    // Combine both maps into one
    reverseMap.forEach((key, value) {
      map[key] = value;
    });

    mirrorMap = map;
    //console.log(`mirrored chars parsed in ${performance.now() - start}ms`)
  }
}

getMirroredCharacter (char) {
  parse();
  return mirrorMap[char];
}

/**
 * Given a string and its resolved embedding levels, build a map of indices to replacement chars
 * for any characters in right-to-left segments that have defined mirrored characters.
 * @param string
 * @param embeddingLevels
 * @param [start]
 * @param [end]
 * @return {Map<number, string>}
 */
getMirroredCharactersMap(string, embeddingLevels, int? start, int? end) {
  var strLen = string.length;
  start = Math.max(0, start == null ? 0 : start);
  end = Math.min(strLen - 1, end == null ? strLen - 1 : end);

  var map = new Map();
  for (var i = start; i <= end; i++) {
    if (embeddingLevels[i] & 1) { //only odd (rtl) levels
      var mirror = getMirroredCharacter(string[i]);
      if (mirror != null) {
        map[i] = mirror;
      }
    }
  }
  return map;
}
