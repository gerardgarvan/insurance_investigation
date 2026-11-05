"""
Unit tests for tracked-change builders in am_manual_lib.py.

Tests cover:
- IdAllocator collision-free ID allocation
- make_tracked_paragraph structure (w:pPr/w:rPr/w:ins mark + w:ins run)
- make_tracked_paragraph xml:space=preserve for leading/trailing space
- reject_all removes an inserted paragraph entirely; text equals pre-insert state
- accept_all keeps inserted text
- apply_correction on "foo BAR baz" → reject gives "foo BAR baz"; accept gives "foo QUX baz"
"""

import copy
import sys
from pathlib import Path

import pytest
from lxml import etree

# Make the am_evidence package importable
TOOLS_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(TOOLS_DIR))

from am_evidence import am_manual_lib as m  # noqa: E402

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
W14 = "http://schemas.microsoft.com/office/word/2010/wordml"
AUTHOR = "Gerard Garvan"
DATE = "2026-10-28T00:00:00Z"


def qn(ns, local):
    return f"{{{ns}}}{local}"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_simple_doc(para_texts):
    """
    Build a minimal w:document tree containing one w:body with the given paragraphs.
    Returns the root element (w:document).
    """
    NS_MAP = {"w": W, "w14": W14}
    doc = etree.Element(qn(W, "document"), nsmap=NS_MAP)
    body = etree.SubElement(doc, qn(W, "body"))
    for idx, text in enumerate(para_texts):
        p = etree.SubElement(body, qn(W, "p"))
        p.set(f"{{{W14}}}paraId", f"AABB{idx:04X}")
        r = etree.SubElement(p, qn(W, "r"))
        t = etree.SubElement(r, qn(W, "t"))
        t.text = text
    return doc


# ---------------------------------------------------------------------------
# IdAllocator tests
# ---------------------------------------------------------------------------

class TestIdAllocator:
    def test_next_w_id_starts_above_existing(self):
        alloc = m.IdAllocator(w_ids={0, 1}, para_ids=set(), durable_ids=set())
        assert alloc.next_w_id() == 2

    def test_next_w_id_monotonic(self):
        alloc = m.IdAllocator(w_ids={0, 1}, para_ids=set(), durable_ids=set())
        ids = [alloc.next_w_id() for _ in range(5)]
        assert ids == sorted(ids)
        assert len(set(ids)) == len(ids)

    def test_next_para_id_never_in_existing_set(self):
        existing = {"7FF8A73E", "7FF8A73F", "7FF8A740"}
        alloc = m.IdAllocator(w_ids=set(), para_ids=existing, durable_ids=set())
        new_ids = {alloc.next_para_id() for _ in range(10)}
        assert new_ids.isdisjoint(existing)

    def test_next_para_id_uppercase_hex_8_chars(self):
        alloc = m.IdAllocator(w_ids=set(), para_ids=set(), durable_ids=set())
        pid = alloc.next_para_id()
        assert len(pid) == 8
        assert pid == pid.upper()
        int(pid, 16)  # must parse as hex

    def test_issued_w_ids_tracked(self):
        alloc = m.IdAllocator(w_ids={0, 1}, para_ids=set(), durable_ids=set())
        alloc.next_w_id()
        alloc.next_w_id()
        assert len(alloc.issued_w_ids) == 2


# ---------------------------------------------------------------------------
# make_tracked_paragraph tests
# ---------------------------------------------------------------------------

class TestMakeTrackedParagraph:
    def _get_para(self, text=" hello "):
        para_id = "DEADBEEF"
        return m.make_tracked_paragraph(
            text=text, rev_id=10, author=AUTHOR, date=DATE,
            para_id=para_id, run_rev_id=11,
        )

    def test_has_pPr_rPr_ins_mark(self):
        p = self._get_para()
        pPr = p.find(qn(W, "pPr"))
        assert pPr is not None, "w:pPr missing"
        rPr = pPr.find(qn(W, "rPr"))
        assert rPr is not None, "w:rPr in pPr missing"
        ins_mark = rPr.find(qn(W, "ins"))
        assert ins_mark is not None, "w:ins mark in w:pPr/w:rPr missing"
        assert ins_mark.get(qn(W, "author")) == AUTHOR

    def test_has_ins_run_wrapper(self):
        p = self._get_para()
        ins = p.find(qn(W, "ins"))
        assert ins is not None, "run-level w:ins missing"
        r = ins.find(qn(W, "r"))
        assert r is not None, "w:r inside w:ins missing"

    def test_text_content(self):
        p = self._get_para("hello world")
        all_t = "".join(el.text or "" for el in p.iter(qn(W, "t")))
        assert "hello world" in all_t

    def test_xml_space_preserve_leading_space(self):
        p = self._get_para(" leading")
        t_els = list(p.iter(qn(W, "t")))
        assert len(t_els) > 0
        # The run's w:t should have xml:space=preserve
        t = t_els[-1]  # last w:t is the run text
        assert t.get("{http://www.w3.org/XML/1998/namespace}space") == "preserve"

    def test_xml_space_preserve_trailing_space(self):
        p = self._get_para("trailing ")
        t_els = list(p.iter(qn(W, "t")))
        t = t_els[-1]
        assert t.get("{http://www.w3.org/XML/1998/namespace}space") == "preserve"

    def test_no_xml_space_preserve_no_space(self):
        p = self._get_para("nospace")
        t_els = list(p.iter(qn(W, "t")))
        t = t_els[-1]
        # Should NOT have xml:space=preserve when no leading/trailing space
        assert t.get("{http://www.w3.org/XML/1998/namespace}space") is None

    def test_para_id_attribute_set(self):
        p = self._get_para()
        assert p.get(qn(W14, "paraId")) == "DEADBEEF"

    def test_ins_ids_set(self):
        p = self._get_para()
        pPr = p.find(qn(W, "pPr"))
        rPr = pPr.find(qn(W, "rPr"))
        mark = rPr.find(qn(W, "ins"))
        assert mark.get(qn(W, "id")) == "10"
        ins = p.find(qn(W, "ins"))
        assert ins.get(qn(W, "id")) == "11"


# ---------------------------------------------------------------------------
# reject_all / accept_all with an inserted paragraph
# ---------------------------------------------------------------------------

class TestRejectAcceptInsertedParagraph:
    """
    Build a document with one original paragraph, insert a tracked paragraph,
    then verify reject_all removes it and accept_all keeps it.
    """

    def _setup(self):
        doc = _make_simple_doc(["Original text"])
        alloc = m.IdAllocator(w_ids={0, 1}, para_ids={"AABB0000"}, durable_ids=set())
        para_id = alloc.next_para_id()
        mark_id = alloc.next_w_id()
        run_id = alloc.next_w_id()
        new_para = m.make_tracked_paragraph(
            text="Inserted text",
            rev_id=mark_id,
            author=AUTHOR,
            date=DATE,
            para_id=para_id,
            run_rev_id=run_id,
        )
        body = doc.find(qn(W, "body"))
        body.append(new_para)
        return doc, alloc, para_id

    def _get_all_text(self, doc):
        texts = []
        for p in doc.iter(qn(W, "p")):
            t = "".join(el.text or "" for el in p.iter(qn(W, "t")))
            if t:
                texts.append(t)
        return texts

    def test_reject_all_removes_inserted_paragraph(self):
        doc, alloc, para_id = self._setup()
        # Register issued paraId so reject_all can find it
        m._REJECT_ALL_ISSUED_PARA_IDS = set(alloc.issued_para_ids)
        doc_copy = copy.deepcopy(doc)
        m.reject_all(doc_copy, set(alloc.issued_w_ids))
        texts = self._get_all_text(doc_copy)
        assert "Inserted text" not in " ".join(texts)
        assert "Original text" in " ".join(texts)

    def test_reject_all_text_equals_original(self):
        doc, alloc, para_id = self._setup()
        m._REJECT_ALL_ISSUED_PARA_IDS = set(alloc.issued_para_ids)
        # Collect original texts before insertion
        original_texts = ["Original text"]
        doc_copy = copy.deepcopy(doc)
        m.reject_all(doc_copy, set(alloc.issued_w_ids))
        result_texts = [
            "".join(el.text or "" for el in p.iter(qn(W, "t")))
            for p in doc_copy.iter(qn(W, "p"))
            if "".join(el.text or "" for el in p.iter(qn(W, "t")))
        ]
        assert result_texts == original_texts

    def test_accept_all_keeps_inserted_text(self):
        doc, alloc, para_id = self._setup()
        doc_copy = copy.deepcopy(doc)
        m.accept_all(doc_copy, set(alloc.issued_w_ids))
        texts = self._get_all_text(doc_copy)
        assert "Inserted text" in " ".join(texts)
        assert "Original text" in " ".join(texts)


# ---------------------------------------------------------------------------
# apply_correction round-trip tests
# ---------------------------------------------------------------------------

class TestApplyCorrectionRoundTrip:
    """
    Build a document with 'foo BAR baz', apply a REPLACE correction to change
    BAR → QUX, then verify reject gives 'foo BAR baz' and accept gives 'foo QUX baz'.
    """

    def _setup(self):
        doc = _make_simple_doc(["foo BAR baz"])
        alloc = m.IdAllocator(w_ids={0, 1}, para_ids={"AABB0000"}, durable_ids=set())
        m.apply_correction(doc, "BAR", "QUX", alloc, AUTHOR, DATE)
        return doc, alloc

    def _full_text(self, doc):
        return "".join(
            el.text or ""
            for el in doc.iter(qn(W, "t"))
        )

    def _full_text_del(self, doc):
        """Text from w:delText elements (deleted content)."""
        return "".join(
            el.text or ""
            for el in doc.iter(qn(W, "delText"))
        )

    def test_reject_gives_original_text(self):
        doc, alloc = self._setup()
        m._REJECT_ALL_ISSUED_PARA_IDS = set(alloc.issued_para_ids)
        doc_copy = copy.deepcopy(doc)
        m.reject_all(doc_copy, set(alloc.issued_w_ids))
        text = "".join(
            el.text or ""
            for el in doc_copy.iter(qn(W, "t"))
        )
        assert text == "foo BAR baz", f"Expected 'foo BAR baz', got {text!r}"

    def test_accept_gives_replaced_text(self):
        doc, alloc = self._setup()
        doc_copy = copy.deepcopy(doc)
        m.accept_all(doc_copy, set(alloc.issued_w_ids))
        text = "".join(
            el.text or ""
            for el in doc_copy.iter(qn(W, "t"))
        )
        assert "QUX" in text, f"Expected QUX in text, got {text!r}"
        assert "BAR" not in text, f"Expected BAR removed, got {text!r}"
        assert "foo" in text and "baz" in text, f"Context missing: {text!r}"

    def test_deleted_element_contains_anchor(self):
        doc, alloc = self._setup()
        # Before reject/accept, the w:del should contain "BAR"
        del_text = self._full_text_del(doc)
        assert "BAR" in del_text, f"Expected BAR in w:delText, got {del_text!r}"


# ---------------------------------------------------------------------------
# enable_track_revisions
# ---------------------------------------------------------------------------

class TestEnableTrackRevisions:
    def _make_settings(self, with_track_changes=False):
        root = etree.Element(qn(W, "settings"), nsmap={"w": W})
        if with_track_changes:
            etree.SubElement(root, qn(W, "trackChanges"))
        return etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)

    def test_adds_track_changes_when_absent(self):
        settings = self._make_settings(with_track_changes=False)
        result = m.enable_track_revisions(settings)
        tree = etree.fromstring(result)
        assert tree.find(qn(W, "trackChanges")) is not None

    def test_idempotent_when_already_present(self):
        settings = self._make_settings(with_track_changes=True)
        result = m.enable_track_revisions(settings)
        tree = etree.fromstring(result)
        # Should still be present (and only once)
        found = tree.findall(qn(W, "trackChanges"))
        assert len(found) == 1
