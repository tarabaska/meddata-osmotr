# -*- coding: utf-8 -*-
"""Собирает читаемый PDF из файла осмотра.

    python3 osmotr_pdf.py "Фамилия - Код.json"

Кладёт рядом «Фамилия - Код.pdf». Один лист, для врача и для истории болезни.
"""
import json
import os
import sys

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph,
                                Spacer, Table, TableStyle)

FONTS = "/System/Library/Fonts/Supplemental/"
pdfmetrics.registerFont(TTFont("B", FONTS + "Arial.ttf"))
pdfmetrics.registerFont(TTFont("BB", FONTS + "Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("S", FONTS + "Georgia.ttf"))
pdfmetrics.registerFont(TTFont("SB", FONTS + "Georgia Bold.ttf"))

INK = colors.HexColor("#14201E")
MUTED = colors.HexColor("#5E6D6A")
ACCENT = colors.HexColor("#136B5E")
LINE = colors.HexColor("#CBD6D3")
SOFT = colors.HexColor("#EDF3F1")

AOFAS = {
    "a_pain": ("Боль", 40, {"40": "Нет", "30": "Слабая, время от времени",
                            "20": "Умеренная, ежедневно", "0": "Сильная, почти постоянно"}),
    "a_act": ("Ограничения и опора", 10,
              {"10": "Ограничений нет, опора не нужна",
               "7": "Дела без ограничений, досуг ограничен",
               "4": "Ограничены дела и досуг, трость",
               "0": "Резкое ограничение: ходунки, костыли, коляска"}),
    "a_dist": ("Максимальная дистанция", 5,
               {"5": "Больше шести кварталов", "4": "Четыре — шесть",
                "2": "Один — три", "0": "Меньше одного"}),
    "a_surf": ("Поверхности", 5,
               {"5": "Везде без затруднений",
                "3": "Затруднения на неровном, лестницах",
                "0": "Резкие затруднения"}),
    "a_gait": ("Походка", 8, {"8": "Норма или лёгкое нарушение",
                              "4": "Явное нарушение", "0": "Выраженное нарушение"}),
    "a_sag": ("Сагиттальная амплитуда", 8,
              {"8": "Норма или лёгкое ограничение, 30° и более",
               "4": "Умеренное ограничение, 15–29°", "0": "Резкое ограничение, менее 15°"}),
    "a_hind": ("Движения заднего отдела", 6,
               {"6": "Норма или лёгкое ограничение, 75–100%",
                "3": "Умеренное ограничение, 25–74%", "0": "Выраженное, менее 25%"}),
    "a_stab": ("Стабильность", 8, {"8": "Стабилен", "0": "Явно нестабилен"}),
    "a_al": ("Ось", 10, {"10": "Хорошая, стопа плантиградна",
                         "5": "Удовлетворительная, жалоб нет",
                         "0": "Плохая, грубое нарушение оси"}),
}

TESTS = [("ad", "Передний выдвижной ящик"), ("tt", "Наклон таранной кости"),
         ("dfer", "Тыльное сгибание с наружной ротацией"), ("sq", "Тест сдавления"),
         ("ev", "Эверсионный стресс-тест")]


def build(src, dst=None):
    with open(src, encoding="utf-8") as fh:
        doc_data = json.load(fh)
    d = doc_data.get("d") or doc_data.get("data") or {}
    a = doc_data.get("a") or doc_data.get("aofas") or {}

    if dst is None:
        dst = os.path.splitext(src)[0] + ".pdf"

    s_h1 = ParagraphStyle("h1", fontName="SB", fontSize=15, leading=17, textColor=INK)
    s_meta = ParagraphStyle("m", fontName="B", fontSize=9, leading=12, textColor=MUTED)
    s_sec = ParagraphStyle("s", fontName="BB", fontSize=8, leading=10, textColor=ACCENT,
                           spaceBefore=9, spaceAfter=3)
    s_k = ParagraphStyle("k", fontName="B", fontSize=8.5, leading=11, textColor=MUTED)
    s_v = ParagraphStyle("v", fontName="BB", fontSize=8.5, leading=11, textColor=INK)
    s_foot = ParagraphStyle("f", fontName="B", fontSize=7, leading=9, textColor=MUTED)

    pw, ph = A4
    m = 15 * mm
    cw = pw - 2 * m

    def pairs(rows, cols=2):
        cells = []
        for k, v in rows:
            cells.append([Paragraph(k, s_k), Paragraph(str(v), s_v)])
        out, row = [], []
        for c in cells:
            row.extend(c)
            if len(row) == cols * 2:
                out.append(row)
                row = []
        if row:
            while len(row) < cols * 2:
                row.append("")
            out.append(row)
        colw = [cw / cols * 0.48, cw / cols * 0.52] * cols
        t = Table(out, colWidths=colw)
        t.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 2.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
            ("LINEBELOW", (0, 0), (-1, -2), 0.3, LINE),
        ]))
        return t

    def g(key, dash="—"):
        v = d.get(key)
        return v if v not in (None, "") else dash

    def rom(side):
        parts = [d.get("rom_%s1" % side), d.get("rom_%s2" % side), d.get("rom_%s3" % side)]
        if not any(parts):
            return "—"
        txt = "-".join(p if p else "0" for p in parts)
        tot = d.get("rom_%st" % side)
        return txt + (" (итого %s)" % tot if tot else "")

    def pr(side, pref):
        p, b = d.get("%s_%sp" % (pref, side)), d.get("%s_%sb" % (pref, side))
        if not p and not b:
            return "—"
        return "сила %s, боль %s" % (p or "—", b or "—")

    st = []
    st.append(Paragraph("Осмотр после перелома лодыжек", s_h1))
    who = " · ".join(x for x in [g("fio", ""), g("code", ""), ("осмотр " + g("date", "")) if d.get("date") else ""] if x)
    st.append(Paragraph(who, s_meta))
    st.append(Spacer(1, 6))

    st.append(Paragraph("ПАЦИЕНТ И ВИЗИТ", s_sec))
    st.append(pairs([
        ("Дата операции", g("opdate")), ("Дней с операции", g("days")),
        ("Дата рождения", g("dob")), ("Возраст на момент операции", g("age")),
        ("Сторона", g("side")), ("Код в исследовании", g("code")),
    ]))

    st.append(Paragraph("ИЗМЕРЕНИЯ", s_sec))
    vol = "—"
    if d.get("vol_r") and d.get("vol_l"):
        try:
            vol = "П %s · Л %s (разница %s)" % (
                d["vol_r"], d["vol_l"],
                round(abs(float(str(d["vol_r"]).replace(",", ".")) - float(str(d["vol_l"]).replace(",", "."))), 1))
        except Exception:
            vol = "П %s · Л %s" % (d["vol_r"], d["vol_l"])
    rows = [
        ("Амплитуда, правая", rom("r")), ("Амплитуда, левая", rom("l")),
        ("Окружность у медиальной лодыжки, см", vol), ("Боль при ходьбе, 0–10", g("painwalk")),
        ("Тыльное сгибание, правая", pr("r", "df")), ("Тыльное сгибание, левая", pr("l", "df")),
        ("Разгибание, правая", pr("r", "ex")), ("Разгибание, левая", pr("l", "ex")),
        ("Максимальная дистанция, км", g("maxkm")), ("Ходьба с костылями, недель", g("crutchw")),
        ("Хромота", g("limp")), ("Рана", g("wound")),
        ("Артроз, Kellgren–Lawrence", g("arth")), ("Тендинит", g("tend")),
    ]
    for key, title in TESTS:
        rows.append((title, "П %s · Л %s" % (d.get(key + "_r") or "—", d.get(key + "_l") or "—")))
    st.append(pairs(rows))

    st.append(Paragraph("ШКАЛА AOFAS", s_sec))
    ar = []
    for key, (title, maxp, opts) in AOFAS.items():
        val = d.get(key)
        chosen = opts.get(val, "не отмечено") if val is not None else "не отмечено"
        pts = ("%s из %s" % (val, maxp)) if val not in (None, "") else "— из %s" % maxp
        ar.append([Paragraph(title, s_k), Paragraph(chosen, s_v), Paragraph(pts, s_k)])
    t = Table(ar, colWidths=[cw * 0.26, cw * 0.56, cw * 0.18])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("BACKGROUND", (0, 0), (-1, -1), SOFT),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, colors.white),
        ("ALIGN", (2, 0), (2, -1), "RIGHT"),
    ]))
    st.append(t)
    st.append(Spacer(1, 5))

    total = a.get("total", "—")
    tot = Table([[Paragraph("Итого AOFAS", ParagraphStyle("x", fontName="BB", fontSize=10,
                                                          textColor=colors.white)),
                  Paragraph("%s из 100" % total, ParagraphStyle("y", fontName="BB", fontSize=13,
                                                                textColor=colors.white, alignment=2))]],
                colWidths=[cw * 0.6, cw * 0.4])
    tot.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), ACCENT),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    st.append(tot)

    if d.get("comment"):
        st.append(Paragraph("КОММЕНТАРИЙ", s_sec))
        st.append(Paragraph(d["comment"], s_v))

    st.append(Spacer(1, 8))
    st.append(Paragraph(
        "Сформировано автоматически из файла осмотра. Машиночитаемая версия — в файле .json рядом.",
        s_foot))

    def bg(canv, _doc):
        canv.saveState()
        canv.setFillColor(colors.white)
        canv.rect(0, 0, pw, ph, stroke=0, fill=1)
        canv.restoreState()

    pdf = BaseDocTemplate(dst, pagesize=A4, leftMargin=m, rightMargin=m,
                          topMargin=m, bottomMargin=12 * mm,
                          title=os.path.basename(dst))
    frame = Frame(m, 12 * mm, cw, ph - m - 12 * mm, id="f",
                  leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    pdf.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=bg)])
    pdf.build(st)
    return dst


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    print(build(sys.argv[1]))
