#!/usr/bin/env python3
"""Generate probe wordlists from hermitdave/FrequencyWords for en/ja/ko.

Inputs (must be present locally — the script does NOT fetch on its own):
  /tmp/freqwords/en_50k.txt
  /tmp/freqwords/ja_full.txt
  /tmp/freqwords/ko_full.txt   (was ko_50k.txt; switched to the full corpus so
                                 the post-lemmatization lemma pool reaches deep
                                 enough to fill RANK_HI=50000)
Fetch with:
  mkdir -p /tmp/freqwords && cd /tmp/freqwords
  curl -fsSL https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt -o en_50k.txt
  curl -fsSL https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ja/ja_full.txt -o ja_full.txt
  curl -fsSL https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ko/ko_full.txt -o ko_full.txt

Korean lemmatization requires `kiwipiepy` (pip install kiwipiepy). A dedicated
venv lives at `./.venv` next to this file; run with:
  ./.venv/bin/python _curate.py
en/ja regeneration does not require kiwipiepy — its import is lazy and limited
to ko_lemma_pipeline().

Writes ../wordlists/{en,ja,ko}.probes.tsv (NUM_PROBES log-spaced probes each,
post-filter for proper nouns / Chinese leakage / inflected fragments).

Filter knobs (en/ja/ko):
- en: requires lowercase entry in /usr/share/dict/words + EN_NAME_BLOCK strikes
  remaining proper nouns the dict still includes (joe/laura/spencer/...).
- ja: hiragana/katakana/kanji presence + JA_BLOCK (places, names, fiction
  artefacts) + JA_REJECT_CHARS (simplified-Chinese-only chars to detect leakage).
- ko: kiwipiepy morphological analysis on each eojeol of ko_full.txt → first
  content morpheme reduced to dictionary form (NNG/NNP/NNB → noun;
  VV/VA/VX → stem+다; noun+XSV/XSA → noun+<suffix>다 where suffix is the
  literal 하/되 morpheme kiwipiepy emits; XR+XSV/XSA → root+<suffix>다;
  MAG/MAJ len≥2 → adverb). Lemmas are re-ranked by aggregated frequency,
  then ko_ok strips KO_BLOCK / non-Hangul / len<2 entries. Lemmas with
  total aggregated count < KO_MIN_COUNT are dropped — single-occurrence
  rare entries from ko_full.txt are mostly subtitle typos / proper nouns.

Re-run after editing OUTPUT_DIR isn't needed — it's resolved relative to this
file's location, so probe TSVs always end up in ../wordlists/.
"""

from __future__ import annotations
import math
import re
import sys
import unicodedata
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent
OUT_DIR.mkdir(parents=True, exist_ok=True)

NUM_PROBES = 200
RANK_LO = 50
RANK_HI = 50000  # global fallback when LANG_CEILING does not specify the lang.

# Per-language probe rank ceiling. Reflects realistic native vocabulary upper
# bounds + the depth our corpora actually deliver. Korean lemma count is
# genuinely smaller than English/Japanese (more compositional / hanja-driven),
# so unifying everyone at 50000 over-rates ko. See plan: kind-gathering-moth.
LANG_CEILING = {
    "en": 60000,   # en_50k + enwiki titles merged → ~85k pool, capped at 60k
                   # to align with testyourvocab native upper bands.
    "ja": 50000,   # NINJAL BCCWJ + JLPT synthetic ranks
    "ko": 45000,   # ko_full + kowiki titles merged → ~42.5k unique lemmas
}

# Stage 3 lower-rank cutoff. Probes below this aren't "rare" enough to
# discriminate between near-native and native — Stage 3 is exclusively the
# upper-band refinement, run only when Stage 1+2 saturate.
RARE_RANK_LO = 15000

# ---------- per-language filters ----------

EN_BLOCK = {
    # keep test out of pure function words; any that slip through are fine
    "the","a","an","of","and","to","in","is","it","on","for","at","as","by",
    "or","so","no","be","my","me","we","he","she","you","they","i","us","them",
    "him","her","his","its","ours","yours","theirs","this","that","these","those",
    "am","are","was","were","been","being","do","does","did","done","doing",
    "have","has","had","having","not","yes","oh","um","uh","ah",
    "if","but","then","than","when","where","why","how","what","who","which",
    "from","into","onto","with","without","about","over","under","up","down",
    "out","off","very","just","also","too","yeah","yes","ok","okay","hi","hey",
    "ll","re","ve","s","t","d","m","ya",
    # contracted/spoken-only fragments common in subtitles
    "gonna","wanna","gotta","kinda","sorta","outta","ain","ya","ye","yer",
    "nope","yep","yup","yo","huh","hmm","ugh","ouch",
}
# Common English first names, surnames, place names, and fictional character
# names that ARE in /usr/share/dict/words (so the dict filter alone can't catch
# them). Subtitle corpora overrepresent these heavily.
EN_NAME_BLOCK = {
    # given names — male
    "joe","tony","john","mike","sam","ben","dan","bob","jim","tom","rick",
    "ron","ray","roy","gary","larry","kevin","brian","steve","mark","matt",
    "alex","bill","will","jack","jake","frank","george","henry","peter","paul",
    "andy","tim","ted","fred","carl","carlos","jose","luis","martin",
    "leo","max","nick","oscar","spencer","ralph","walter","arthur","alfred",
    "oliver","harvey","victor","wallace","clark","derek","grant","lloyd",
    "russell","harold","louis","arnold","edward","albert","norman","stanley",
    "douglas","irving","lyman","ralph","jerry","patrick","dennis","wayne",
    "harry","scott","brandon","jason","gregory","craig","raymond","marcus",
    "antonio","vincent","keith","glenn","gerald","ethan","ivan","jonas",
    # given names — female
    "mary","anna","emma","lily","lucy","kate","sara","sarah","julie","jenny",
    "amy","ann","sandy","donna","rachel","laura","molly","ellen","grace",
    "alice","helen","elaine","edna","barbara","carol","susan","jean","rose",
    "violet","iris","ruby","pearl","kim","megan","betty","janet","brenda",
    "diane","alma","nancy","sheila","jane","linda","marie","ellie","emily",
    # surnames — common US/UK
    "smith","johnson","williams","brown","jones","garcia","davis","miller",
    "wilson","anderson","thomas","taylor","moore","jackson","lee","perez",
    "thompson","white","harris","sanchez","ramirez","lewis","robinson",
    "walker","young","allen","king","wright","torres","hill","flores","green",
    "adams","nelson","baker","hall","rivera","campbell","mitchell","carter",
    "roberts","gomez","phillips","evans","turner","diaz","parker","cruz",
    "edwards","collins","reyes","stewart","morris","morales","murphy","cook",
    "rogers","ortiz","morgan","cooper","peterson","bailey","reed","kelly",
    "howard","ramos","cox","ward","richardson","watson","brooks","chavez",
    "wood","james","bennett","gray","mendoza","ruiz","hughes","price","alvarez",
    "castillo","sanders","myers","long","ross","foster","jimenez","powell",
    "patterson","hamilton","sullivan","sloan","hopper","swain","hastings",
    "wally","scrooge","bunty","yore","tara","hubble","porter","brazil",
    "thanksgiving","banjo","tucker","fisher","carpenter","mason","wells",
    "boone","dixon","pierce","hayes","fox","todd","barnes","ross","gray",
    # place names that pass the dict filter
    "china","japan","korea","france","germany","spain","italy","russia","mexico",
    "boston","seattle","chicago","atlanta","miami","dallas","houston","phoenix",
    "portland","detroit","memphis","denver","austin","brooklyn","manhattan",
    "harlem","oxford","cambridge","manchester","liverpool","glasgow","dublin",
    "vienna","milan","naples","florence","venice","tokyo","kyoto","osaka",
    "shanghai","beijing","seoul","bangkok","mumbai","delhi","cairo",
    "amsterdam","brussels","copenhagen","helsinki","stockholm","warsaw",
    # short fragments/abbreviations that slip through dict
    "lis","tre","mer","syl","gus","abe","mel","cam","des","syl","ves",
}

# Lazy-loaded dict from /usr/share/dict/words (or fallback word list).
_EN_DICT_CACHE: set | None = None
def _load_en_dict() -> set:
    global _EN_DICT_CACHE
    if _EN_DICT_CACHE is not None:
        return _EN_DICT_CACHE
    paths = ["/usr/share/dict/words", "/usr/share/dict/american-english"]
    s: set = set()
    for p in paths:
        if Path(p).exists():
            with open(p, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    w = line.strip()
                    # Only accept entries that are already lowercase in the source.
                    # This is what filters out proper nouns like "Daniel", "London",
                    # "Robert" — the system dict capitalizes those.
                    if w and w == w.lower() and w.isalpha():
                        s.add(w)
            break
    if not s:
        print("WARNING: no system word dict found; en filter will be weak", file=sys.stderr)
    _EN_DICT_CACHE = s
    return s

def en_ok(w: str) -> bool:
    if not re.fullmatch(r"[a-z]{3,}", w):
        return False
    if w in EN_BLOCK or w in EN_NAME_BLOCK:
        return False
    d = _load_en_dict()
    if d and w not in d:
        return False
    return True


# Paths for en sources.
EN_50K_PATH = "/tmp/freqwords/en_50k.txt"
ENWIKI_TITLES_PATH = "/tmp/freqwords/enwiki-titles"

_EN_TITLE_WORD_RE = re.compile(r"[a-z]+")
_EN_TITLE_PARENS = re.compile(r"\s*\([^)]*\)\s*")


def load_en_combined_pool():
    """Combined en corpus → ranked lemma list.

    Sources:
      1. /tmp/freqwords/en_50k.txt — OpenSubtitles 2018 en_50k (50k word+count)
      2. /tmp/freqwords/enwiki-titles — enwiki-latest-all-titles-in-ns0 (~19M titles)

    Each enwiki title is lowercased and split on `[a-z]+` runs; each unique
    word in the title contributes count=1 to that lemma. Combined counts are
    re-ranked by total frequency. The en_ok filter (dict + name/place block)
    is applied to both sources, so ~84k+ real English lemmas survive — enough
    to cover specialized domain vocabulary (medical/legal/scientific/etymo).
    """
    from collections import Counter
    counts: Counter = Counter()
    en_seen = 0
    with open(EN_50K_PATH, encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            en_seen += 1
            w = parts[0].lower()
            try:
                c = int(parts[1])
            except ValueError:
                continue
            if en_ok(w):
                counts[w] += c
    wiki_seen = 0
    if Path(ENWIKI_TITLES_PATH).exists():
        with open(ENWIKI_TITLES_PATH, encoding="utf-8") as f:
            next(f, None)  # skip "page_title" header
            for line in f:
                title = line.strip()
                if not title:
                    continue
                wiki_seen += 1
                cleaned = _EN_TITLE_PARENS.sub(
                    " ", title.replace("_", " ").lower()
                )
                # de-dupe within a single title — count=1 per title contribution
                for w in set(_EN_TITLE_WORD_RE.findall(cleaned)):
                    if en_ok(w):
                        counts[w] += 1
    ranked = sorted(counts.items(), key=lambda x: -x[1])
    print(
        f"en: en_50k {en_seen} entries + enwiki titles {wiki_seen} → "
        f"{len(counts)} unique lemmas",
        file=sys.stderr,
    )
    return [(i + 1, w) for i, (w, _) in enumerate(ranked)]

# Japanese: keep words containing CJK Unified Ideographs OR length>=2 of Hiragana/Katakana
HIRA = re.compile(r"[぀-ゟ]")
KATA = re.compile(r"[゠-ヿ]")
KANJI = re.compile(r"[一-鿿]")
JA_BLOCK = {
    # particles / fillers / fragments
    "の","は","が","を","に","と","で","へ","も","や","か","ね","よ","な","だ","ば",
    "い","う","え","お","あ","ん","つ","く","き","し","す","せ","そ","た","て","ち",
    "じゃ","でも","ただ","とか","まあ","まだ","もう","もし","です","ます","だから",
    "あの","この","その","どの","それ","これ","あれ","どれ",
    "私","僕","俺","君","彼","彼女","あなた","お前","これ","そこ","そして","それ",
    "んだ","のだ","だな","かな","かも","じゃあ","じゃない","でしょ","でしょう",
    "けど","から","まで","だけ","しか","こそ","くらい","ぐらい","ながら",
    "うん","ええ","はい","いえ","ああ","おお","あっ","おい","ねえ","ふん",
    "ない","いる","ある","する","なる","くる","いく",
    "言","行","知","思","見","聞","来","帰","出","入","食","住","住む","死","生","泣","笑",
    # countries / places / proper nouns (subtitle artefacts)
    "アメリカ","日本","中国","韓国","ロシア","フランス","ドイツ","イギリス","イタリア",
    "東京","大阪","京都","横浜","札幌","名古屋","福岡","沖縄","金沢","市ヶ谷","三条",
    "ニューヨーク","ロンドン","パリ","ハリウッド","ハワイ",
    # personal names common in subtitles (kanji)
    "義彦","太郎","花子","健一","美咲","健司","幸子","美子","明子","和子","裕子",
    "翔太","拓也","健太","隆司","真司","真一","裕一","健太郎","直人","友美",
    "明美","直子","真理","千秋","裕美","由美","良子","知子","美穂","真希",
    "速人","銀次","岩崎","田中","鈴木","佐藤","山田","渡辺","伊藤","加藤",
    "中村","小林","松本","木村","清水","山本","高橋","斎藤","吉田","橋本",
    # fiction / katakana names (subtitle character names)
    "ウィンガーディアム","殺せん","ブリリアム","ノベリア","トリア","アマルガム","ピーター",
    "メアリー","ジョン","マイク","トニー","ロバート","ダニエル","スペンサー",
    "アメリア","モリアティー","アランゴ","エミリー","ジェニー","ジェシカ","リサ",
    "サラ","ローラ","アンナ","エマ","オリビア","ソフィア","ミア","エヴァ",
    "アレックス","クリス","ジェイク","ジェームズ","マイケル","ニック","ライアン",
    "ハリー","ロン","ハーマイオニー","ダンブルドア","スネイプ","ヴォルデモート",
    # surface-form fragments (verbs missing trailing okurigana from corpus tokenizer).
    # Be conservative: ONLY block patterns that are not valid as standalone nouns.
    # Real words like 思い (thought) / 考え (thought) / 怒り (anger) / 通り (street) /
    # 続き (sequel) / 出来 (ability) MUST stay in the pool.
    "言い直","吸い上げ","言いつか","走り回れ","運き","受け取","受け入れ",
    "立ち止ま","聞き出","引き出","読み取","書き取","取り組","見つか",
    "作り出","作り上げ","切り取","切り出","抜き出","付け加","降り立",
    "出来上が","関わ","聞こえ","世離れ","空げ","強がり","捜さ","話さ",
    # Chinese-grammar fragments / corrupt high-rank entries
    "輩子","地磁","あてっ",
    # vulgar / NSFW (avoid surfacing in a vocabulary test)
    "糞女","糞野","短小","クソ","糞",
    # bracket/garbage tokens
    "丶あ","金主に","南側","岩崎","真犯人",
}
# Additional reject pattern: words ending in single grammatical particle.
JA_TRAILING_PARTICLES = ("に","を","は","が","で","へ","も","と","や","か","の")
# Characters that are simplified-Chinese-only (not used in Japanese), used to
# detect Chinese leakage from subtitle corpora into the JA frequency list.
JA_REJECT_CHARS = set("们这复实远过会经买卖东书听说问讲语体长无价简见办响边变认识设试运达"
                      "门马龙国语龟齐贝钱银银鱼鸟虫亚来时东师风马门问识价后"
                      "动伸传来与对发战块层产党别"
                      # corrupt / out-of-Japanese punctuation glyphs from subtitle data
                      "丶")

KATA_ONLY = re.compile(r"^[゠-ヿー]+$")
HIRA_ONLY = re.compile(r"^[぀-ゟー]+$")
# Mimetic / onomatopoeic words (擬態語・擬音語). These are valid Japanese but
# heavily skew the test against L2 learners — natives know them all from age 5
# while advanced L2 learners typically miss them. Filtered out so the score
# reflects "literary / Sino-Japanese / common content vocabulary" growth.
# Reduplication patterns (XX-XX, XXX-XXX, XXXX-XXXX) catch most automatically.
JA_MIMETIC_REDUP_2 = re.compile(r"^([぀-ゟ]{2})\1$")  # ぎらぎら, ぽかぽか
JA_MIMETIC_REDUP_3 = re.compile(r"^([぀-ゟ]{3})\1$")  # うじゃうじゃ, しゃあしゃあ
JA_MIMETIC_REDUP_4 = re.compile(r"^([぀-ゟ]{4})\1$")  # rare but possible
# Curated explicit list — non-reduplication ABCD-pattern mimetic adverbs.
JA_MIMETIC_BLOCK = {
    "ほんのり","しっくり","がっしり","ぐったり","ぼんやり","しんみり","じっくり",
    "うっかり","のんびり","ゆっくり","しっとり","しっかり","ぐっすり","ばっちり",
    "きっぱり","がっかり","ぴったり","びっくり","すっきり","ばっさり","がっつり",
    "あっさり","ひっそり","じっと","ぱっと","さっと","すっと","ふっと","ぐっと",
    "ぱりっ","かりっ","しゃきっ","つるっ","ふわっ","ぱっと","しんと","じめじめ",
    "じわじわ","ふらふら","ぐらぐら","ぴかぴか","つるつる","さらさら","ぴかっ",
    "ぴたっ","ぴーん","がやがや","ざわざわ","ばたばた","ぱたぱた","どたばた",
    "わくわく","どきどき","はらはら","にこにこ","にやにや","ぐすぐす","ぼろぼろ",
    "へとへと","くたくた","ぼろぼろ","ぼそぼそ","ぶつぶつ","ごろごろ","ころころ",
    "ぐるぐる","くるくる","ぴょんぴょん","ぴゅんぴゅん","ぴゅーん","ぼーっと",
    "あふあふ","あたふた","おっとり","おどおど","かさかさ","かちかち","くしゃくしゃ",
    "もくもく","のろのろ","へろへろ","ぺこぺこ","ぼーぼー","ぽつぽつ","しょんぼり",
    "ずきずき","ぞくぞく","とぼとぼ","のっそり","ぴりぴり","ぶよぶよ","へなへな",
    "ぼうっと","めらめら","もぞもぞ","ゆらゆら","よろよろ","わあわあ",
    # short clipped onomatopoeia (1-3 hiragana that cue mimetic feel)
    "ごーん","きゅん","づら","にべ","がん","がた","がく","おもろ","づか",
    "うさ","がちゃ","づる","ぱっ","ぴっ","とん","どん","かん","ぱん",
    "ずり","ぞろり","かちり",
    # additional ABCD-pattern mimetics surfaced from BCCWJ probe inspection
    "こんがり","さっくり","しどろもどろ","きっかり","かっちり","こざっぱり",
    "ちっぽけ","くるり","ぴしり","ふんわり","こっそり","てっきり","ばっちり",
    "じゃっかん","ふつふつ","ほっこり","ぷりぷり","ぷんぷん","ぱりぱり",
    "ふんわり","ひんやり","じわっと","ふわふわ","ねっとり","のろま",
    # NSFW slang occasionally tagged as common nouns by BCCWJ
    "ちんぽ","まんこ","おっぱい",
}

def ja_ok(w: str, rank: int = 0) -> bool:
    # Drop tokens with any non-Japanese letter or digit/punct
    if any(unicodedata.category(c).startswith(("P","N","Z","S","C")) for c in w):
        return False
    if not (KANJI.search(w) or HIRA.search(w) or KATA.search(w)):
        return False
    # require length >= 2 chars unless it's a kanji compound (>=1 kanji)
    if len(w) < 2:
        if not KANJI.fullmatch(w):
            return False
        return False  # single kanji often verb stem; skip to avoid ambiguity
    if w in JA_BLOCK:
        return False
    # reject Chinese leakage (simplified-only chars not used in Japanese)
    if any(c in JA_REJECT_CHARS for c in w):
        return False
    # reject "<word><particle>" tokens — corpus glued a particle to the head
    if len(w) >= 3 and w[-1] in JA_TRAILING_PARTICLES:
        # but allow some legitimate compounds ending in these chars (の特例)
        # require some bias — only reject when last char is に/を/が/は/で which
        # are unambiguous case markers
        if w[-1] in ("に", "を", "が", "は", "で"):
            return False
    # reject katakana-only words >= 4 chars at high rank (most are character
    # names from anime/movies; common loanwords are usually shorter or earlier)
    if rank >= 1500 and KATA_ONLY.fullmatch(w) and len(w) >= 4:
        return False
    # reject mimetic / onomatopoeic words (see JA_MIMETIC_* above)
    if w in JA_MIMETIC_BLOCK:
        return False
    if HIRA_ONLY.fullmatch(w):
        if (JA_MIMETIC_REDUP_2.fullmatch(w)
                or JA_MIMETIC_REDUP_3.fullmatch(w)
                or JA_MIMETIC_REDUP_4.fullmatch(w)):
            return False
    # reject "kanji + hiragana + kanji" stem fragments (e.g., 言い直 missing 直す's す)
    # heuristic: starts kanji, has 1-2 hiragana in middle, ends kanji
    if (len(w) >= 3 and KANJI.fullmatch(w[0]) and KANJI.fullmatch(w[-1])
            and all(HIRA.fullmatch(c) for c in w[1:-1])):
        return False
    return True

HANGUL = re.compile(r"^[가-힣]+$")
KO_BLOCK = {
    "그","난","넌","난","너","나","우리","자기","당신","여러분",
    "이","그","저","것","거","수","때","곳","것","좀","저",
    "은","는","이","가","을","를","의","에","에서","에게","와","과",
    "도","만","까지","부터","처럼","보다","마다","조차",
    "응","음","어","아","오","에","예","네","아니","아니오","네","글쎄",
    "그래","그럼","그럼요","그치","그래서","그러나","그리고","하지만",
    "있","없","하","되","오","가","주","받","보","먹","듣","말",
    "그게","그건","이게","저게","이건","저건",
    "그래도","그러면","그러니까","그러므로","그래서",
    "아주","매우","너무","정말","진짜","좀","조금","많이","약간",
    "다","뭐","뭔","뭐가","뭘","왜","어떻게","언제","어디","누구","누가",
    "더","덜","또","또한","역시","바로","곧","거의","겨우","바로",
    # countries / places / proper nouns from subtitles
    "텍사스","뉴욕","런던","파리","도쿄","베이징","서울","부산",
    "미국","영국","일본","중국","독일","프랑스","러시아","이탈리아","한국",
    "할리우드","하와이",
    # common foreign names
    "마이크","데이비드","로버트","존","피터","톰","제니","사라","리사","제이크",
    "알렉스","크리스","앤디","케빈","니콜","리처드","제임스","마이클","대니얼","에디",
    "브라이언","울프","스펜서",
    # subtitle character names (additional, from kiwi-lemmatized OpenSubtitles ko)
    "루크","버크","노아","수잔","패트릭","벤자민","리스","웰스","주디스","스웨거",
    "에미","퍼거스","심슨","주마리","닥터베일리","메이저","머니","레드","본즈",
    "정이","조지","캘리","켈리","쿠퍼","클램프","윌리엄스","마사","플로이드",
    "레스터","키타노","슈나이더","스토익",
    "메러디스","클레어","찰리","로즈","엠마","마일스","버지니아","클린턴",
    "앤서니","아돌프","트레이시","펠리시","질리언","데보라",
    "지미","리차드","마이애미","마리오","번키","데드풀","시버트","케렌",
    "아카츠키","베일리","데렉","하워드","레베카","드와이트","조셉","아벨",
    "라파엘","뉴트","클라우뎃","플레밍","브리",
    # kiwipiepy misanalyses (whole-eojeol → spurious NNP / synthetic -하다)
    "나도야","다그다","빕하다","까진",
}

def ko_ok(w: str) -> bool:
    if not HANGUL.fullmatch(w):
        return False
    if len(w) < 2:
        return False
    if w in KO_BLOCK:
        return False
    return True

# ---------- Korean lemmatization (kiwipiepy) ----------

# NNP (proper noun) intentionally excluded — kiwipiepy tags subtitle character
# names (조지/캘리/베일리/...) as NNP, which floods the high-rank end of the
# probe list. NNG (common noun) and NNB (dependent noun) are sufficient for
# vocabulary measurement.
KO_POS_NOUN = {"NNG", "NNB"}
KO_POS_VERB = {"VV", "VA", "VX", "VV-I", "VA-I", "VX-I"}
KO_POS_ADV = {"MAG", "MAJ"}
KO_POS_DERIV = {"XSV", "XSA"}  # 하 derivation suffixes
# Note: KO_MIN_COUNT (singleton-drop threshold) was removed when kowiki titles
# joined the pool — NNP/oov filters in _ko_pick_lemma already eliminate the
# typo/proper-noun noise that the threshold previously addressed, and dropping
# singletons would also lose rare-but-real specialized vocabulary that ko_full
# only hits once but kowiki titles attest.


def _ko_pick_lemma(tokens):
    """Reduce a kiwipiepy analysis to a single dictionary form (lemma).

    Returns the lemma string or None to discard the eojeol.
    """
    if not tokens:
        return None
    t0 = tokens[0]
    t1 = tokens[1] if len(tokens) > 1 else None
    t2 = tokens[2] if len(tokens) > 2 else None

    # MAG of length 1 (안/더/또/...) — peek past it for the real content head
    if t0.tag in KO_POS_ADV and len(t0.form) == 1:
        if t1 and t1.tag in KO_POS_VERB:
            return t1.form + "다"
        if t1 and t1.tag in KO_POS_NOUN:
            if t2 and t2.tag in KO_POS_DERIV:
                return t1.form + t2.form + "다"
            return t1.form
        return None

    if t0.tag in KO_POS_NOUN:
        # OOV (out-of-vocabulary) NNG tokens are eojeols kiwipiepy could not
        # decompose against its dictionary — overwhelmingly subtitle character
        # names and typos (히친스/타이렐/에드먼즈의/...). Drop them.
        if getattr(t0, "oov", False):
            return None
        # noun + XSV/XSA → noun + <suffix>다. Suffix is usually 하 (→ 미안하다,
        # 공부하다) but kiwipiepy also tags 되 as XSV (공통된 → 공통/NNG + 되/XSV
        # → 공통되다). Use the suffix form verbatim instead of hard-coding 하.
        if t1 and t1.tag in KO_POS_DERIV:
            return t0.form + t1.form + "다"
        return t0.form

    if t0.tag in KO_POS_VERB:
        # Single-character verb/adjective stems (그/오/가/하 ...) are too
        # ambiguous to surface as a probe — they typically come from misanalyzed
        # contractions (그지/그죠/그러죠 → VA 그). Skip them; the proper lemma
        # surfaces from a less-contracted form elsewhere.
        if len(t0.form) < 2:
            return None
        return t0.form + "다"

    if t0.tag == "XR":
        if t1 and t1.tag in KO_POS_DERIV:
            return t0.form + t1.form + "다"
        return None  # standalone root not useful as a probe

    if t0.tag in KO_POS_ADV and len(t0.form) >= 2:
        return t0.form

    return None


def _ko_load_kiwi():
    try:
        from kiwipiepy import Kiwi
        return Kiwi()
    except ImportError:
        sys.exit(
            "ko regeneration requires kiwipiepy. Install with:\n"
            "  python3 -m venv ./.venv && ./.venv/bin/pip install kiwipiepy\n"
            "Then re-run via:\n"
            "  ./.venv/bin/python _curate.py"
        )


def _ko_count_eojeol_file(path: str, kiwi):
    """ko_full-style file: `eojeol\\tcount` per line. Returns (Counter, seen_lines)."""
    from collections import Counter
    counts: Counter = Counter()
    seen = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            seen += 1
            try:
                c = int(parts[1])
            except ValueError:
                continue
            try:
                tokens = kiwi.analyze(parts[0], top_n=1)[0][0]
            except Exception:
                continue
            lemma = _ko_pick_lemma(tokens)
            if lemma and ko_ok(lemma):
                counts[lemma] += c
    return counts, seen


_HANGUL_SEARCH = re.compile(r"[가-힣]")
_KOWIKI_PAREN = re.compile(r"\s*\([^)]*\)\s*")


def _ko_count_titles_file(path: str, kiwi):
    """kowiki-titles file: one article title per line (header `page_title` first).

    For each title containing Hangul, run kiwi over the cleaned form and add 1
    to every NNG/NNB content morpheme (oov-filtered) and every VV/VA stem
    (length ≥ 2, lemma = stem+다). Titles are deliberately treated as count=1
    sources — Wikipedia title frequency reflects topic existence, not corpus
    frequency, so weighting by 1 keeps the rank ordering driven by ko_full.
    """
    from collections import Counter
    counts: Counter = Counter()
    seen = 0
    if not Path(path).exists():
        return counts, seen
    with open(path, encoding="utf-8") as f:
        next(f, None)  # skip "page_title" header
        for line in f:
            title = line.strip()
            if not title or not _HANGUL_SEARCH.search(title):
                continue
            seen += 1
            cleaned = _KOWIKI_PAREN.sub(" ", title.replace("_", " "))
            try:
                tokens = kiwi.analyze(cleaned, top_n=1)[0][0]
            except Exception:
                continue
            for t in tokens:
                if t.tag in KO_POS_NOUN and not getattr(t, "oov", False):
                    if ko_ok(t.form):
                        counts[t.form] += 1
                elif t.tag in KO_POS_VERB and len(t.form) >= 2:
                    lemma = t.form + "다"
                    if ko_ok(lemma):
                        counts[lemma] += 1
    return counts, seen


# Paths for ko sources.
KO_FULL_PATH = "/tmp/freqwords/ko_full.txt"
KOWIKI_TITLES_PATH = "/tmp/freqwords/kowiki-titles"


def load_ko_lemma_pool():
    """Combined ko corpus → ranked lemma list.

    Sources:
      1. /tmp/freqwords/ko_full.txt — OpenSubtitles 2018 ko_full (688k eojeol+count)
      2. /tmp/freqwords/kowiki-titles — kowiki-latest-all-titles-in-ns0.gz (1.6M titles)
    Combined: lemma counts summed across sources, then ranked by total. Source 1
    dominates rank ordering; source 2 mostly contributes new specialized lemmas
    in the long tail (rank 28k+).

    Returns list[(rank:int, lemma:str)] sorted ascending by rank (1 = most frequent).
    """
    from collections import Counter
    kiwi = _ko_load_kiwi()
    ko_counts, ko_seen = _ko_count_eojeol_file(KO_FULL_PATH, kiwi)
    wiki_counts, wiki_seen = _ko_count_titles_file(KOWIKI_TITLES_PATH, kiwi)
    combined: Counter = Counter(ko_counts)
    for w, c in wiki_counts.items():
        combined[w] += c
    ranked = sorted(combined.items(), key=lambda x: -x[1])
    print(
        f"ko: ko_full {ko_seen} eojeol + kowiki titles {wiki_seen} → "
        f"{len(combined)} unique lemmas (ko_full alone: {len(ko_counts)})",
        file=sys.stderr,
    )
    return [(i + 1, w) for i, (w, _) in enumerate(ranked)]


LANG_CFG = {
    # en combines OpenSubtitles en_50k.txt with enwiki article titles, both
    # passed through the /usr/share/dict + EN_NAME_BLOCK filter so only real
    # English lemmas survive. Wiki titles add domain-specific rare vocabulary
    # (medical/legal/scientific/etymological) past en_50k's coverage. See
    # load_en_combined_pool().
    "en": ("__EN_COMBINED__", en_ok),
    # ko combines OpenSubtitles ko_full + kowiki article titles, lemmatized by
    # kiwipiepy and re-ranked by aggregated lemma frequency. Two output files
    # are produced for ko: ko.probes.tsv (Stage 1+2) and ko.rare.tsv (Stage 3).
    # See load_ko_lemma_pool().
    "ko": ("__KO_KIWI__", ko_ok),
    # ja uses NINJAL BCCWJ short-unit-word frequency list — actual lemma
    # frequencies covering 185k entries, pre-tokenized and POS-tagged. See
    # load_bccwj_pool() — it short-circuits load_candidates() / pick_log_spaced().
    "ja": ("__BCCWJ__", ja_ok),
}

BCCWJ_TSV = Path("/tmp/BCCWJ_frequencylist_suw_ver1_0.tsv")
# BCCWJ POS tags to keep — content words only. Reject all 固有名詞 (proper nouns),
# all 助詞/助動詞 (particles/auxiliaries), 接頭辞/接尾辞 (affixes), pronouns,
# numerals, interjections, symbols.
BCCWJ_KEEP_POS_PREFIX = (
    "名詞-普通名詞-",
    "動詞-一般",
    "形容詞-一般",
    "形状詞-",
    "副詞",
    "連体詞",
)
# Lemma rewrites — disambiguate BCCWJ's citation form when it can be confused
# with a homographic word. Key = BCCWJ lemma, value = display form shown in
# probes. Add entries here when probe inspection surfaces ambiguity (e.g. the
# adverb さら / 更 lemma collides visually with the noun 皿). Surface form must
# remain a real, recognizable Japanese word.
JA_LEMMA_REWRITE = {
    "さら": "さらに",  # adverb 更 — disambiguate from noun 皿 (rank 81496)
    # Archaic-kanji forms whose modern dictionary headword is the kana form.
    # MeCab/BCCWJ surfaces the kanji as the lemma, but modern Japanese writes
    # these almost exclusively in kana. Rewriting here keeps the rank slot
    # (so log-spaced sampling is unaffected) while testing the form a native
    # speaker actually encounters. Limit strictly to demonstratives /
    # interrogatives / a few adverbs whose 大辞林・広辞苑 headword is kana.
    "其の": "その",
    "此の": "この",
    "其れ": "それ",
    "此れ": "これ",
    "彼の": "あの",
    "彼方": "あちら",
    "其方": "そちら",
    "此方": "こちら",
    "彼処": "あそこ",
    "其処": "そこ",
    "此処": "ここ",
    "何処": "どこ",
    "何時": "いつ",
    "何故": "なぜ",
    "何方": "どちら",
    "兎に角": "とにかく",
    "兎角": "とかく",
    "凡そ": "およそ",
    "概ね": "おおむね",
    "即ち": "すなわち",
    "寧ろ": "むしろ",
    "頗る": "すこぶる",
    "殆ど": "ほとんど",
    "尤も": "もっとも",
    "若し": "もし",
    "若しくは": "もしくは",
    "滅多に": "めったに",
    "漸く": "ようやく",
    "暫く": "しばらく",
}

# Phantom lemmas — MeCab/BCCWJ surfaces these as verb lemmas when tokenizing
# particle-like constructions (e.g. 〜に於いて → 於く+いて). They are not used
# as standalone verbs in modern Japanese and not listed in 広辞苑/大辞林.
# Drop them entirely from the curated pool.
JA_LEMMA_DROP = {
    "於く",      # phantom from 〜に於いて
    "於ける",    # phantom from 〜に於ける
}

def load_bccwj_pool():
    """Read NINJAL BCCWJ SUW frequency list.

    Source: NINJAL (clrd.ninjal.ac.jp/bccwj/freq-list.html).
    Licence: free for research/educational use.
    Columns of interest: rank (1), lemma (3), pos (4).
    Filtering: keeps content words by POS prefix, drops proper nouns / particles
    / pronouns / numerals / affixes. The retained rank is the original BCCWJ
    rank — `pick_log_spaced` then samples log-spaced over [RANK_LO, RANK_HI].
    """
    if not BCCWJ_TSV.exists():
        print(f"WARNING: {BCCWJ_TSV} missing; ja list will be empty", file=sys.stderr)
        return []
    out = []
    with open(BCCWJ_TSV, encoding="utf-8") as f:
        next(f)  # header
        for line in f:
            cols = line.split("\t")
            if len(cols) < 4:
                continue
            try:
                rank = int(cols[0])
            except ValueError:
                continue
            lemma = cols[2].strip()
            pos = cols[3].strip()
            if not lemma:
                continue
            if not any(pos.startswith(p) for p in BCCWJ_KEEP_POS_PREFIX):
                continue
            # apply ja_ok content filters (NSFW block, etc.)
            if not ja_ok(lemma, rank=rank):
                continue
            if lemma in JA_LEMMA_DROP:
                continue
            lemma = JA_LEMMA_REWRITE.get(lemma, lemma)
            out.append((rank, lemma))
    return out

JLPT_DIR = Path("/tmp/jlpt")
JLPT_LEVELS = ("n5", "n4", "n3", "n2", "n1")  # easiest → hardest

def load_jlpt_pool():
    """Read JLPT n5..n1 (CC: MIT, elzup/jlpt-word-list); dedup preserving the
    easier-level appearance; assign synthetic ranks log-spaced over [50, 30000].

    Returns list[(rank:int, word:str)] sorted by rank.
    """
    if not JLPT_DIR.exists():
        print(f"WARNING: {JLPT_DIR} missing; ja list will be empty", file=sys.stderr)
        return []
    import csv
    entries = []  # ordered: easier first
    seen = set()
    for level in JLPT_LEVELS:
        p = JLPT_DIR / f"{level}.csv"
        if not p.exists():
            continue
        with open(p, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                w = (row.get("expression") or "").strip()
                if not w or w in seen:
                    continue
                # Apply ja_ok content filters (still want to drop NSFW etc.)
                if not ja_ok(w, rank=0):
                    continue
                seen.add(w)
                entries.append(w)
    n = len(entries)
    if n == 0:
        return []
    out = []
    for i, w in enumerate(entries):
        denom = max(1, n - 1)
        r = round(RANK_LO * (RANK_HI / RANK_LO) ** (i / denom))
        out.append((r, w))
    return out

def load_candidates(path: str, ok):
    """Walk the corpus once. The line number is the frequency rank.

    `ok` is called with (word, rank); langs that ignore rank just take a
    default arg.
    """
    import inspect
    pass_rank = "rank" in inspect.signature(ok).parameters
    out = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            parts = line.strip().split()
            if not parts:
                continue
            w = parts[0]
            ok_result = ok(w, i) if pass_rank else ok(w)
            if ok_result:
                out.append((i, w))
    return out

def pick_log_spaced(candidates, n, lo, hi):
    targets = []
    for k in range(n):
        # log-spaced target rank
        t = lo * (hi / lo) ** (k / (n - 1))
        targets.append(round(t))
    # for each target, pick the candidate (rank, word) with rank closest >= target;
    # if none above, pick closest below; ensure no duplicate words
    by_rank = sorted(candidates)
    chosen = []
    used = set()
    pos_hint = 0
    for t in targets:
        # binary search would be better; linear ok for 50k
        # advance pos_hint until rank >= t
        while pos_hint < len(by_rank) and by_rank[pos_hint][0] < t:
            pos_hint += 1
        # try forward then backward to find an unused word
        forward = pos_hint
        backward = pos_hint - 1
        picked = None
        for _ in range(len(by_rank)):
            if forward < len(by_rank) and by_rank[forward][1] not in used:
                picked = by_rank[forward]
                break
            if backward >= 0 and by_rank[backward][1] not in used:
                picked = by_rank[backward]
                break
            forward += 1
            backward -= 1
            if forward >= len(by_rank) and backward < 0:
                break
        if picked is None:
            continue
        used.add(picked[1])
        chosen.append(picked)
    chosen.sort()
    return chosen

LICENSE_HEADER_BY_LANG = {
    "en": (
        "# Sources: hermitdave/FrequencyWords (https://github.com/hermitdave/FrequencyWords)\n"
        "#          + enwiki-latest-all-titles-in-ns0 (https://dumps.wikimedia.org/enwiki/latest/)\n"
        "# Licences: CC-BY-SA 4.0 (both sources).\n"
        "# Methodology: en_50k word counts merged with enwiki title-token counts (each unique\n"
        "#   word per title contributes count=1). All entries pass en_ok: must be /usr/share/dict\n"
        "#   lowercase entry, not in EN_BLOCK / EN_NAME_BLOCK. ~85k unique lemmas after filter.\n"
        "#   Wiki contribution mostly populates rank 30k+ with domain-specific rare vocabulary\n"
        "#   (medical/legal/scientific/etymological). Two slices are emitted: en.probes.tsv\n"
        "#   (Stage 1+2, ranks ~50–60000) and en.rare.tsv (Stage 3, ranks 15000–60000).\n"
    ),
    "ko": (
        "# Source: hermitdave/FrequencyWords (https://github.com/hermitdave/FrequencyWords)\n"
        "# Licence: CC-BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)\n"
    ),
    "ja": (
        "# Source: NINJAL BCCWJ short-unit-word frequency list (https://clrd.ninjal.ac.jp/bccwj/freq-list.html)\n"
        "# Licence: free for research/educational use (NINJAL public).\n"
        "# Methodology: lemma-level frequency from the Balanced Corpus of Contemporary Written Japanese.\n"
        "#   Filtered to content POS only (名詞-普通名詞-*, 動詞-一般, 形容詞-一般, 形状詞-*, 副詞, 連体詞);\n"
        "#   all 固有名詞 (proper nouns), particles, auxiliaries, affixes, pronouns, numerals, and symbols\n"
        "#   are dropped. Ranks are real BCCWJ frequency ranks.\n"
    ),
}
LICENSE_HEADER_TRAIL = (
    "# Curated probe subset for /vocab level test (vocabulary size estimation, testyourvocab-style).\n"
)
LANG_CAVEAT = {
    "ko": (
        "# Methodology: combined corpus of OpenSubtitles ko_full.txt (688k eojeol+count) and the\n"
        "#   kowiki-latest-all-titles-in-ns0 dump (~1.6M article titles). Both are morphologically\n"
        "#   analyzed with kiwipiepy; for ko_full only the first content morpheme of each eojeol is\n"
        "#   kept and reduced to dictionary form, while every NNG/NNB/VV/VA content morpheme inside\n"
        "#   each Wikipedia title is counted (count=1 per title). Lemma forms: NNG/NNB → noun;\n"
        "#   VV/VA/VX → stem+다; noun+XSV/XSA → noun+<suffix>다 where suffix is the literal 하/되\n"
        "#   emitted by kiwipiepy; XR+XSV/XSA same; MAG/MAJ length≥2 → adverb. NNP (proper nouns)\n"
        "#   and OOV NNG tokens are dropped — they are overwhelmingly subtitle character names or\n"
        "#   typos. Counts are summed across sources; the resulting list is re-ranked by total\n"
        "#   aggregated frequency. Two slices are emitted: ko.probes.tsv (rank ~50 to ko ceiling,\n"
        "#   Stage 1+2 use) and ko.rare.tsv (rank 15000 to ko ceiling, Stage 3 dense upper-band\n"
        "#   sampling). Korean per-lang ceiling is set to 45000 — see LANG_CEILING in _curate.py.\n"
    ),
}
HEADER_TAIL = "# Format: rank<TAB>word<TAB>pos<TAB>note   (pos/note optional, currently empty)\n"

def write_tsv(lang, picks, suffix="probes"):
    """Write a probe file. suffix='probes' → <lang>.probes.tsv (Stage 1+2);
    suffix='rare' → <lang>.rare.tsv (Stage 3)."""
    out = OUT_DIR / f"{lang}.{suffix}.tsv"
    with open(out, "w", encoding="utf-8") as f:
        f.write(LICENSE_HEADER_BY_LANG.get(lang, ""))
        f.write(LICENSE_HEADER_TRAIL)
        if lang in LANG_CAVEAT:
            f.write(LANG_CAVEAT[lang])
        f.write(HEADER_TAIL)
        f.write("rank\tword\tpos\tnote\n")
        for rank, word in picks:
            f.write(f"{rank}\t{word}\t\t\n")
    print(f"{lang}: wrote {len(picks)} probes -> {out}")

def main():
    for lang, (path, ok) in LANG_CFG.items():
        if path == "__BCCWJ__":
            cands = load_bccwj_pool()
        elif path == "__JLPT__":
            cands = load_jlpt_pool()
        elif path == "__KO_KIWI__":
            cands = load_ko_lemma_pool()
        elif path == "__EN_COMBINED__":
            cands = load_en_combined_pool()
        else:
            cands = load_candidates(path, ok)
        if not cands:
            print(f"{lang}: no candidates found at {path}", file=sys.stderr)
            continue
        max_rank = cands[-1][0]
        ceiling = LANG_CEILING.get(lang, RANK_HI)
        hi = min(ceiling, max_rank)
        picks = pick_log_spaced(cands, NUM_PROBES, RANK_LO, hi)
        write_tsv(lang, picks, suffix="probes")
        # Stage 3 rare-probe file — emitted for every language. ko uses
        # ko_full + kowiki, ja uses BCCWJ, en uses en_50k + enwiki titles.
        if max_rank > RARE_RANK_LO:
            rare = pick_log_spaced(cands, NUM_PROBES, RARE_RANK_LO, hi)
            write_tsv(lang, rare, suffix="rare")

if __name__ == "__main__":
    main()
