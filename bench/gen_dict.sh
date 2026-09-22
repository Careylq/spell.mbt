#!/usr/bin/env bash
#
# bench/gen_dict.sh — deterministic synthetic `.aff`/`.dic` generator and word-list
# generator for the performance benchmark.
#
# These files are NOT real language data. They exist only to measure how dictionary
# load time and per-word checking time scale with dictionary *size*, holding the
# affix-rule shape fixed. See bench/README.md for why that is the interesting axis.
#
# Shape (fixed, no RNG — word i is a pure function of i)
# ------------------------------------------------------
# * Syllables: a fixed 20-item table
#       ba cre dil fen gor hul jan kel lum mor nep or pyr quen ral sor tor ven wix zor
# * Word i = base-20 encoding of i into exactly 5 syllables (most significant first),
#   followed by an ending marker selected by i % 5:
#       0 -> ""     1 -> "y"     2 -> "sh"     3 -> "el"     4 -> "or"
#   Appending the marker keeps the map i -> word injective, so every word is distinct.
#   The encoding covers 20^5 = 3,200,000 distinct indices.
# * Flags (short/single-character flag mode, the Hunspell default since the `.aff`
#   has no `FLAG` line): every word carries `S`; `D` is added when i % 2 == 0,
#   `G` when i % 3 == 0, `U` when i % 5 == 0, `R` when i % 7 == 0.
# * Affix file: `SET UTF-8`, a 26-letter `TRY`, and **5 blocks / 8 rules**:
#       SFX S  Y  3 :  "0 s ."   "0 es [sxzh]"   "y ies [^aeiou]y"
#       SFX D  Y  2 :  "0 ed ."  "0 ing ."
#       SFX G  Y  1 :  "0 ly ."
#       PFX U  Y  1 :  "0 un ."
#       PFX R  Y  1 :  "0 re ."
#
# Usage
# -----
#   bash bench/gen_dict.sh <entry-count> <output-dir>
#       writes <output-dir>/synthetic.aff and <output-dir>/synthetic.dic
#       and prints a one-line machine-readable summary on stdout.
#
#   bash bench/gen_dict.sh --words <count> <output-file>
#       writes <count> distinct synthetic words, one per line (the same word
#       function, without a dictionary around it).
#
# Exit status: 0 on success, 1 on bad usage / unwritable output.

set -uo pipefail

usage() {
  cat <<'USAGE_EOF'
bench/gen_dict.sh — deterministic synthetic .aff/.dic and word-list generator.

Usage:
  bash bench/gen_dict.sh <entry-count> <output-dir>
      writes <output-dir>/synthetic.aff and <output-dir>/synthetic.dic
  bash bench/gen_dict.sh --words <count> <output-file>
      writes <count> distinct synthetic words, one per line

See the header of this file for the exact (fixed, no-RNG) shape of the data.
USAGE_EOF
}

# The affine generator, shared by both modes. `count` words starting at index 0.
gen_words() { # $1 = count  -> one word per line on stdout
  awk -v count="$1" '
    BEGIN {
      split("ba cre dil fen gor hul jan kel lum mor nep or pyr quen ral sor tor ven wix zor", syl, " ")
      marker[0] = ""; marker[1] = "y"; marker[2] = "sh"; marker[3] = "el"; marker[4] = "or"
      for (i = 0; i < count; i++) {
        idx = i
        word = ""
        for (d = 0; d < 5; d++) {
          word = syl[(idx % 20) + 1] word
          idx = int(idx / 20)
        }
        print word marker[i % 5]
      }
    }
  '
}

MODE="${1:-}"
case "$MODE" in
  --words)
    COUNT="${2:-}"; OUT="${3:-}"
    if [ -z "$COUNT" ] || [ -z "$OUT" ]; then
      echo "ERROR: --words needs <count> <output-file>" >&2
      exit 1
    fi
    gen_words "$COUNT" > "$OUT" || exit 1
    echo "wrote $COUNT synthetic words -> $OUT"
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    COUNT="$1"; OUTDIR="${2:-}"
    if [ -z "$OUTDIR" ]; then
      echo "ERROR: gen_dict.sh needs <entry-count> <output-dir>" >&2
      exit 1
    fi
    case "$COUNT" in
      ''|*[!0-9]*) echo "ERROR: entry count must be a positive integer, got '$COUNT'" >&2; exit 1 ;;
    esac
    if [ "$COUNT" -lt 1 ]; then
      echo "ERROR: entry count must be >= 1" >&2
      exit 1
    fi
    mkdir -p "$OUTDIR" || { echo "ERROR: cannot create $OUTDIR" >&2; exit 1; }
    AFF="$OUTDIR/synthetic.aff"
    DIC="$OUTDIR/synthetic.dic"

    cat > "$AFF" <<'AFF_EOF'
SET UTF-8
TRY abcdefghijklmnopqrstuvwxyz
SFX S Y 3
SFX S 0 s .
SFX S 0 es [sxzh]
SFX S y ies [^aeiou]y
SFX D Y 2
SFX D 0 ed .
SFX D 0 ing .
SFX G Y 1
SFX G 0 ly .
PFX U Y 1
PFX U 0 un .
PFX R Y 1
PFX R 0 re .
AFF_EOF

    # `.dic`: declared count on line 1, then `word/flags`, flags omitted when empty.
    {
      echo "$COUNT"
      awk -v count="$COUNT" '
        BEGIN {
          split("ba cre dil fen gor hul jan kel lum mor nep or pyr quen ral sor tor ven wix zor", syl, " ")
          marker[0] = ""; marker[1] = "y"; marker[2] = "sh"; marker[3] = "el"; marker[4] = "or"
          for (i = 0; i < count; i++) {
            idx = i
            word = ""
            for (d = 0; d < 5; d++) {
              word = syl[(idx % 20) + 1] word
              idx = int(idx / 20)
            }
            f = "S"
            if (i % 2 == 0) f = f "D"
            if (i % 3 == 0) f = f "G"
            if (i % 5 == 0) f = f "U"
            if (i % 7 == 0) f = f "R"
            printf "%s/%s\n", word marker[i % 5], f
          }
        }
      '
    } > "$DIC"

    [ -s "$DIC" ] || { echo "ERROR: generated .dic is empty" >&2; exit 1; }

    # One-line machine-readable summary for the caller. `affix_rules` counts the
    # rule lines (`PFX/SFX flag strip add condition`); block header lines carry
    # `Y`/`N` in the cross-product column instead.
    aff_sha="$(shasum -a 256 "$AFF" 2>/dev/null | awk '{print $1}')"
    dic_sha="$(shasum -a 256 "$DIC" 2>/dev/null | awk '{print $1}')"
    dic_bytes="$(wc -c < "$DIC" | tr -d ' ')"
    rule_lines="$(awk '$1=="PFX"||$1=="SFX"{ if ($3!="Y" && $3!="N") n++ } END{print n+0}' "$AFF")"
    rule_blocks="$(awk '$1=="PFX"||$1=="SFX"{print $2}' "$AFF" | sort -u | wc -l | tr -d ' ')"
    echo "entries=$COUNT dic_bytes=$dic_bytes affix_rules=$rule_lines affix_blocks=$rule_blocks aff_sha256=$aff_sha dic_sha256=$dic_sha"
    ;;
esac
