#!/usr/bin/env python3
"""Build apps/mobile/assets/geo/cities.json — the offline city list for prayer setup (spec §5.5).

    python3 tools/geo/build_cities.py

Source: npm `city-timezones` 1.3.4 (MIT; Natural Earth populated places with IANA time zones),
pinned by sha512. Keeps every city in MENA countries plus the largest cities worldwide, up to LIMIT.
Arabic display names come from AR_NAMES below (geography only); other cities show their English name.
Row format: [nameEn, nameAr | null, iso2, lat, lng, timezone].
"""
from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from npm_fetch import fetch  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/mobile/assets/geo/cities.json"
URL = "https://registry.npmjs.org/city-timezones/-/city-timezones-1.3.4.tgz"
INTEGRITY = "sha512-yLmtCxU4y5HLAw9XGIMcGEXO+R2KH1sb595wEQC/E9BxSDpazCD7v9ZQRySO7367IXWsWqt3z2xFVh3OkZdgEQ=="
LIMIT = 1500
MENA = set("EG SA AE KW QA BH OM YE JO PS LB SY IQ LY TN DZ MA SD MR".split())

COUNTRIES_AR = {
    "EG": "مصر", "SA": "السعودية", "AE": "الإمارات", "KW": "الكويت", "QA": "قطر", "BH": "البحرين", "OM": "عُمان",
    "YE": "اليمن", "JO": "الأردن", "PS": "فلسطين", "LB": "لبنان", "SY": "سوريا", "IQ": "العراق", "LY": "ليبيا",
    "TN": "تونس", "DZ": "الجزائر", "MA": "المغرب", "SD": "السودان", "MR": "موريتانيا", "TR": "تركيا",
    "GB": "المملكة المتحدة", "US": "الولايات المتحدة", "CA": "كندا", "DE": "ألمانيا", "FR": "فرنسا",
    "IT": "إيطاليا", "ES": "إسبانيا", "NL": "هولندا", "BE": "بلجيكا", "SE": "السويد", "AU": "أستراليا",
    "MY": "ماليزيا", "ID": "إندونيسيا", "PK": "باكستان", "IN": "الهند", "BD": "بنغلاديش", "NG": "نيجيريا",
}

AR_NAMES = {
    ("EG", "Cairo"): "القاهرة", ("EG", "Alexandria"): "الإسكندرية", ("EG", "El Giza"): "الجيزة",
    ("EG", "Bur Said"): "بورسعيد", ("EG", "Luxor"): "الأقصر", ("EG", "El Mansura"): "المنصورة", ("EG", "Suez"): "السويس",
    ("EG", "Ismailia"): "الإسماعيلية", ("EG", "Asyut"): "أسيوط", ("EG", "Tanta"): "طنطا", ("EG", "Sohag"): "سوهاج",
    ("EG", "Damanhur"): "دمنهور", ("EG", "El Minya"): "المنيا", ("EG", "Beni Suef"): "بني سويف", ("EG", "El Faiyum"): "الفيوم",
    ("EG", "Zagazig"): "الزقازيق", ("EG", "Aswan"): "أسوان", ("EG", "Qena"): "قنا", ("EG", "Dumyat"): "دمياط",
    ("EG", "Shibin el Kom"): "شبين الكوم", ("EG", "Kom Ombo"): "كوم أمبو", ("EG", "Mallawi"): "ملوي", ("EG", "Benha"): "بنها",
    ("EG", "Hurghada"): "الغردقة", ("EG", "El Arish"): "العريش", ("EG", "Kafr el Sheikh"): "كفر الشيخ",
    ("EG", "El Kharga"): "الخارجة", ("EG", "Siwa"): "سيوة", ("EG", "Isna"): "إسنا", ("EG", "Rashid"): "رشيد",
    ("SA", "Riyadh"): "الرياض", ("SA", "Jeddah"): "جدة", ("SA", "Ad Damman"): "الدمام", ("SA", "Makkah"): "مكة المكرمة",
    ("SA", "Medina"): "المدينة المنورة", ("SA", "At Taif"): "الطائف", ("SA", "Al Hufuf"): "الهفوف", ("SA", "Tabuk"): "تبوك",
    ("SA", "Abha"): "أبها", ("SA", "Buraydah"): "بريدة", ("SA", "Hail"): "حائل", ("SA", "Jizan"): "جازان",
    ("SA", "Najran"): "نجران", ("SA", "Yanbu al Bahr"): "ينبع", ("SA", "Al Jubayl"): "الجبيل", 
    ("AE", "Dubai"): "دبي", ("AE", "Sharjah"): "الشارقة", ("AE", "Abu Dhabi"): "أبوظبي", ("AE", "Al Ayn"): "العين",
    ("AE", "Ras al Khaymah"): "رأس الخيمة", ("AE", "Al Fujayrah"): "الفجيرة", ("AE", "Umm al Qaywayn"): "أم القيوين",
    ("KW", "Kuwait"): "الكويت", ("KW", "Al Jahra"): "الجهراء", ("KW", "Hawalli"): "حولي", ("KW", "Al Ahmadi"): "الأحمدي",
    ("QA", "Doha"): "الدوحة", ("BH", "Manama"): "المنامة",
    ("OM", "Muscat"): "مسقط", ("OM", "As Sib"): "السيب", ("OM", "Salalah"): "صلالة", ("OM", "Suhar"): "صحار",
    ("OM", "Nizwa"): "نزوى", ("OM", "Sur"): "صور", ("OM", "Ibri"): "عبري",
    ("YE", "Sanaa"): "صنعاء", ("YE", "Aden"): "عدن", ("YE", "Taizz"): "تعز", ("YE", "Al Hudaydah"): "الحديدة",
    ("YE", "Ibb"): "إب", ("YE", "Al Mukalla"): "المكلا", ("YE", "Dhamar"): "ذمار",
    ("JO", "Amman"): "عمّان", ("JO", "Az Zarqa"): "الزرقاء", ("JO", "Irbid"): "إربد", ("JO", "As Salt"): "السلط",
    ("JO", "Al Aqabah"): "العقبة", ("JO", "Al Mafraq"): "المفرق", ("JO", "Al Karak"): "الكرك",
    ("PS", "Gaza"): "غزة", ("PS", "Al Khalil"): "الخليل", ("PS", "Nablus"): "نابلس", ("PS", "Ramallah"): "رام الله",
    ("LB", "Beirut"): "بيروت", ("LB", "Trablous"): "طرابلس", ("LB", "Saida"): "صيدا", ("LB", "Zahle"): "زحلة",
    ("SY", "Damascus"): "دمشق", ("SY", "Aleppo"): "حلب", ("SY", "Hims"): "حمص", ("SY", "Hamah"): "حماة",
    ("SY", "Al Ladhiqiyah"): "اللاذقية", ("SY", "Dayr az Zawr"): "دير الزور", ("SY", "Ar Raqqah"): "الرقة",
    ("IQ", "Baghdad"): "بغداد", ("IQ", "Mosul"): "الموصل", ("IQ", "Basra"): "البصرة", ("IQ", "Irbil"): "أربيل",
    ("IQ", "As Sulaymaniyah"): "السليمانية", ("IQ", "Dahuk"): "دهوك", ("IQ", "An Najaf"): "النجف", ("IQ", "Kirkuk"): "كركوك",
    ("IQ", "Karbala"): "كربلاء",
    ("LY", "Tripoli"): "طرابلس", ("LY", "Banghazi"): "بنغازي", ("LY", "Misratah"): "مصراتة", ("LY", "Az Zawiyah"): "الزاوية",
    ("LY", "Al Khums"): "الخمس", ("LY", "Tubruq"): "طبرق", ("LY", "Ajdabiya"): "أجدابيا", ("LY", "Sabha"): "سبها",
    ("TN", "Tunis"): "تونس", ("TN", "Sfax"): "صفاقس", ("TN", "Sousse"): "سوسة", ("TN", "Gabes"): "قابس",
    ("TN", "Qairouan"): "القيروان", ("TN", "Bizerte"): "بنزرت", ("TN", "Nabeul"): "نابل",
    ("DZ", "Algiers"): "الجزائر", ("DZ", "Oran"): "وهران", ("DZ", "Constantine"): "قسنطينة", ("DZ", "Blida"): "البليدة",
    ("DZ", "Annaba"): "عنابة", ("DZ", "Setif"): "سطيف", ("DZ", "Chlef"): "الشلف", ("DZ", "Batna"): "باتنة",
    ("MA", "Casablanca"): "الدار البيضاء", ("MA", "Rabat"): "الرباط", ("MA", "Fez"): "فاس", ("MA", "Marrakesh"): "مراكش",
    ("MA", "Agadir"): "أكادير", ("MA", "Tangier"): "طنجة", ("MA", "Meknes"): "مكناس", ("MA", "Kenitra"): "القنيطرة",
    ("MA", "Oujda"): "وجدة", 
    ("SD", "Khartoum"): "الخرطوم", ("SD", "Omdurman"): "أم درمان", ("SD", "Port Sudan"): "بورتسودان", ("SD", "Kassala"): "كسلا",
    ("SD", "El Obeid"): "الأبيض", ("SD", "Medani"): "ود مدني", ("SD", "Niyala"): "نيالا",
    ("MR", "Nouakchott"): "نواكشوط", ("MR", "Nouadhibou"): "نواذيبو",
    ("TR", "Istanbul"): "إسطنبول", ("TR", "Ankara"): "أنقرة", ("TR", "Izmir"): "إزمير", ("TR", "Bursa"): "بورصة",
    ("GB", "London"): "لندن", ("GB", "Manchester"): "مانشستر", ("GB", "Birmingham"): "برمنغهام",
    ("FR", "Paris"): "باريس", ("DE", "Berlin"): "برلين", ("US", "New York"): "نيويورك", ("CA", "Toronto"): "تورنتو",
    ("MY", "Kuala Lumpur"): "كوالالمبور", ("ID", "Jakarta"): "جاكرتا", ("PK", "Karachi"): "كراتشي", ("PK", "Lahore"): "لاهور",
}


def main() -> None:
    files = fetch(URL, INTEGRITY)
    cities = json.loads(files["package/data/cityMap.json"])
    seen: set[tuple[str, str]] = set()
    rows = []
    for c in sorted(cities, key=lambda c: (c["iso2"] not in MENA, -float(c["pop"] or 0))):
        key = (c["iso2"], c["city_ascii"])
        if key in seen or not c.get("timezone"):
            continue
        seen.add(key)
        rows.append([c["city_ascii"], AR_NAMES.get(key), c["iso2"], round(c["lat"], 4), round(c["lng"], 4), c["timezone"]])
        if len(rows) >= LIMIT:
            break
    missing = [k for k in AR_NAMES if k not in seen]
    if missing:
        print("note: Arabic names with no matching city (check spelling):", missing)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"countriesAr": COUNTRIES_AR, "cities": rows}, ensure_ascii=False, separators=(",", ":")))
    mena = sum(1 for r in rows if r[2] in MENA)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} cities ({mena} in MENA, {sum(1 for r in rows if r[1])} with Arabic names)")


if __name__ == "__main__":
    main()
