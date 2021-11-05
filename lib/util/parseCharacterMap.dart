part of bidi_dart;

/**
 * Parses an string that holds encoded codepoint mappings, e.g. for bracket pairs or
 * mirroring characters, as encoded by scripts/generateBidiData.js. Returns an object
 * holding the `map`, and optionally a `reverseMap` if `includeReverse:true`.
 * @param {string} encodedString
 * @param {boolean} includeReverse - true if you want reverseMap in the output
 * @return {{map: Map<number, number>, reverseMap?: Map<number, number>}}
 */
parseCharacterMap (encodedString, bool includeReverse) {
  var radix = 36;
  var lastCode = 0;
  var map = new Map();

  Map? reverseMap;

  if(includeReverse) {
    reverseMap = new Map();
  }
  
  var prevPair;

  visit(entry) {
    if (entry.indexOf('+') != -1) {
      var i = num.parse(entry);
      while ( i > 0 ) {
        i--;
        visit(prevPair);
      }
    } else {
      prevPair = entry;
      var _arr = entry.split('>');
      var a = _arr[0];
      var b = _arr[1];

      a = String.fromCharCode(lastCode += int.parse(a, radix: radix));
      b = String.fromCharCode(lastCode += int.parse(b, radix: radix));
      map[a] = b;
      if(includeReverse) reverseMap![b] = a;
    }
  }

  encodedString.split(',').forEach((element) {
    visit(element);
  });

  return { "map": map, "reverseMap": reverseMap };
}
