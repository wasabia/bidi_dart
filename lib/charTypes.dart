part of bidi_dart;

Map<String, int> TYPES = {
  "L": 1,
  "R": 1 << (0 + 1),
  "EN": 1 << (1 + 1),
  "ES": 1 << (2 + 1),
  "ET": 1 << (3 + 1),
  "AN": 1 << (4 + 1),
  "CS": 1 << (5 + 1),
  "B": 1 << (6 + 1),
  "S": 1 << (7 + 1),
  "WS": 1 << (8 + 1),
  "ON": 1 << (9 + 1),
  "BN": 1 << (10 + 1),
  "NSM": 1 << (11 + 1),
  "AL": 1 << (12 + 1),
  "LRO": 1 << (13 + 1),
  "RLO": 1 << (14 + 1),
  "LRE": 1 << (15 + 1),
  "RLE": 1 << (16 + 1),
  "PDF": 1 << (17 + 1),
  "LRI": 1 << (18 + 1),
  "RLI": 1 << (19 + 1),
  "FSI": 1 << (20 + 1),
  "PDI": 1 << (21 + 1)
};
Map<int, String> TYPES_TO_NAMES = {
  1: "L",
  2: "R",
  3: "EN",
  4: "ES",
  5: "ET",
  6: "AN",
  7: "CS",
  8: "B",
  9: "S",
  10: "WS",
  11: "ON",
  12: "BN",
  13: "NSM",
  14: "AL",
  15: "LRO",
  16: "RLO",
  17: "LRE",
  18: "RLE",
  19: "PDF",
  20: "LRI",
  21: "RLI",
  22: "FSI",
  23: "PDI"
};

var ISOLATE_INIT_TYPES = TYPES["LRI"]! | TYPES["RLI"]! | TYPES["FSI"]!;
var STRONG_TYPES = TYPES["L"]! | TYPES["R"]! | TYPES["AL"]!;
var NEUTRAL_ISOLATE_TYPES = TYPES["B"]! | TYPES["S"]! | TYPES["WS"]! | TYPES["ON"]! | TYPES["FSI"]! | TYPES["LRI"]! | TYPES["RLI"]! | TYPES["PDI"]!;
var BN_LIKE_TYPES = TYPES["BN"]! | TYPES["RLE"]! | TYPES["LRE"]! | TYPES["RLO"]! | TYPES["LRO"]! | TYPES["PDF"]!;
var TRAILING_TYPES = TYPES["S"]! | TYPES["WS"]! | TYPES["B"]! | ISOLATE_INIT_TYPES | TYPES["PDI"]! | BN_LIKE_TYPES;

var map = null;

parseData () {
  if (map == null) {
    //var start = performance.now()
    map = new Map();
    for (var type in DATA.keys) {
      if (DATA[type] != null) {
        var lastCode = 0;
        DATA[type]!.split(',').forEach((range) {
          var _rgs = range.split('+');
          var skip_str = _rgs[0];
          var step_str = null;
          if(_rgs.length > 1) {
            step_str = _rgs[1];
          }

          var skip = int.parse(skip_str, radix: 36);
          var step = step_str != null ? int.parse(step_str, radix: 36) : 0;
          map[lastCode += skip] = TYPES[type];
          for (var i = 0; i < step; i++) {
            map[++lastCode] = TYPES[type];
          }
        });
      }
    }
    //console.log(`char types parsed in ${performance.now() - start}ms`)
  }
}

/**
 * @param {string} char
 * @return {number}
 */
getBidiCharType (char) {
  parseData();
  return map[char.codeUnitAt(0)] ?? TYPES["L"];
}

getBidiCharTypeName(char) {
  return TYPES_TO_NAMES[getBidiCharType(char)];
}
