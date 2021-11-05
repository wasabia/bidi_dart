part of bidi_dart;


// import data from './data/bidiBrackets.data.js'
// import { parseCharacterMap } from './util/parseCharacterMap.js'

var openToClose, closeToOpen, canonical;

bracketsParse () {
  if (openToClose == null) {
    //const start = performance.now()
    var _dp = parseCharacterMap(bracketsData["pairs"], true);
    var map = _dp["map"];
    var reverseMap = _dp["reverseMap"];
    
    openToClose = map;
    closeToOpen = reverseMap;
    canonical = parseCharacterMap(bracketsData["canonical"], false).map;
    //console.log(`brackets parsed in ${performance.now() - start}ms`)
  }
}

openingToClosingBracket (char) {
  bracketsParse();
  return openToClose[char];
}

closingToOpeningBracket (char) {
  bracketsParse();
  return closeToOpen[char];
}

getCanonicalBracket (char) {
  bracketsParse();
  return canonical[char];
}
