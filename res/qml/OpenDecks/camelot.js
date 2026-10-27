.pragma library

// Open Decks shows keys in Camelot (design-system §5). Mixxx formats
// `track.keyText` in the user's notation (Traditional by default), so convert
// every notation KeyUtils can emit; anything unrecognised is returned as is.

// Camelot number of the major key on each pitch class (C = 0); a minor key
// shares the number of its relative major, three semitones up.
var majorNumber = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1];
var letterPitch = {C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11};

function camelot(keyText) {
    if (keyText === undefined || keyText === null)
        return "";
    var raw = String(keyText);
    // "7A (Dm)" and "7m (Dm)": the part before the space is the code.
    var text = raw.trim().split(/\s+/)[0];
    if (text === "")
        return "";

    var m = /^0*(1[0-2]|[1-9])([ABab])$/.exec(text);
    if (m)
        return m[1] + m[2].toUpperCase();

    // OpenKey: lancelot number = open key number - 5 (wrapping), m = A, d = B.
    m = /^(1[0-2]|[1-9])([dm])$/.exec(text);
    if (m) {
        var n = parseInt(m[1], 10) - 5;
        if (n < 1)
            n += 12;
        return n + (m[2] === "m" ? "A" : "B");
    }

    // Traditional and ID3 names. "F♯/G♭" and "D♯m/E♭m" carry both spellings;
    // the first one is enough.
    var name = text.split("/")[0];
    m = /^([A-Ga-g])([#♯♭]|b)*(.*)$/.exec(name);
    if (!m)
        return raw;
    var rest = name.substring(1);
    var pitch = letterPitch[m[1].toUpperCase()];
    var i = 0;
    while (i < rest.length && "#♯♭b".indexOf(rest.charAt(i)) >= 0) {
        pitch += rest.charAt(i) === "b" || rest.charAt(i) === "♭" ? -1 : 1;
        ++i;
    }
    var mode = rest.substring(i);
    var minor;
    if (mode === "")
        minor = false;
    else if (/^m(in(or)?)?$/.test(mode) || /^min(or)?$/i.test(mode))
        minor = true;
    else if (/^maj(or)?$/i.test(mode))
        minor = false;
    else
        return raw;
    pitch = ((pitch % 12) + 12) % 12;
    if (minor)
        pitch = (pitch + 3) % 12;
    return majorNumber[pitch] + (minor ? "A" : "B");
}
