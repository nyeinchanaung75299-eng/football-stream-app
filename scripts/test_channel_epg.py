import importlib.util
import gzip
import pathlib
import tempfile
import unittest
from datetime import datetime, timezone

spec=importlib.util.spec_from_file_location('channel_epg',pathlib.Path(__file__).with_name('channel_epg.py'))
epg=importlib.util.module_from_spec(spec);spec.loader.exec_module(epg)

class ChannelEpgTests(unittest.TestCase):
    def test_timezone_and_invalid_wall_time(self):
        self.assertEqual(epg.timestamp('20261108103000 +0530'),epg.timestamp('20261108050000 +0000'))
        self.assertIsNone(epg.timestamp('20260230123000 +0000'))
        self.assertIsNone(epg.timestamp('20261108123000'))

    def test_ambiguous_country_numeric_slots_and_unverified_regions_stay_unbound(self):
        row={'id':'Fox.es','country':'ES','station':'fox','feed':'test','programmes':[{'start':1}]}
        self.assertIsNone(epg.propose_binding({'name':'FOX (NITRO)'},{'fox':[row]}, {}, {})[0])
        self.assertIsNone(epg.propose_binding({'name':'16'}, {'16':[row]}, {}, {})[0])
        self.assertIsNone(epg.propose_binding({'name':'beIN SPORTS Region unverified'}, {}, {}, {})[0])
        self.assertIsNone(epg.propose_binding({'name':'Unknown Sports'}, {'unknownsports':[row]}, {}, {})[0])
        self.assertIsNone(epg.propose_binding({'name':'Sky Sports 1 - AQ'}, {'skysports1':[row]}, {}, {('skysports1','GB'):{'Sky1.gb'}})[0])

    def test_exact_station_and_explicit_region_match_preserves_language_and_variant(self):
        row={'id':'Sports1.au','country':'AU','station':'sports1','feed':'test','programmes':[{'start':1}]}
        index={'sports1':[row]}
        selected,_=epg.propose_binding({'name':'Sports 1 Australia'},index,{}, {})
        self.assertEqual(selected,row)
        self.assertIsNone(epg.propose_binding({'name':'Sports 1 UK'},index,{}, {})[0])
        self.assertNotEqual(epg.station_name('Star Sports 1 Hindi HD'),epg.station_name('Star Sports 1 HD'))
        self.assertNotEqual(epg.station_name('Sky Sports Premier League'),epg.station_name('Sky Sports Football'))
        self.assertNotEqual(epg.station_name('Fox Sports 4K'),epg.station_name('Fox Sports'))
        self.assertNotEqual(epg.station_name('Sky Sport UHD'),epg.station_name('Sky Sport'))
        self.assertEqual(epg.station_name('01:00 WIB Home vs Away Football TNT Sports 3 - AQ'),'tntsports3')
        self.assertEqual(epg.country_hint({'name':'01:00 WIB France vs Portugal Football Tennis Channel - AQ'}),'')
        self.assertEqual(epg.country_hint({'name':'01:00 WIB France vs Portugal Football Tennis Channel USA'}),'US')
        self.assertEqual(epg.country_hint({'name':'Sky Sport F1 DE - AQ'}),'DE')
        self.assertEqual(epg.country_hint({'name':'Zee Cinema','category':'India'}),'IN')
        self.assertEqual(epg.station_name('CBS GOLAZO AQ'),'cbssportsgolazonetwork')
        self.assertEqual(epg.station_name('Eleven Sports 3 Poland'),'elevensports3')
        self.assertEqual(epg.station_name('beIN ENGLISH 1'),epg.station_name('beIN Sports English 1'))
        self.assertNotEqual(epg.station_name('beIN ENGLISH'),epg.station_name('beIN Sports English 1'))

    def test_stale_or_placeholder_programmes_do_not_create_a_fresh_binding(self):
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)/'fixture.xml'
            path.write_text('''<tv><channel id="Sports1.au"><display-name>Sports 1</display-name></channel>
              <programme channel="Sports1.au" start="20251001000000 +0000" stop="20251001020000 +0000"><title>Home vs Away</title></programme>
              <programme channel="Sports1.au" start="20261108000000 +0000" stop="20261108120000 +0000"><title>Off Air</title></programme></tv>''')
            rows=epg.read_feed(('fixture','https://example.invalid/fixture.xml','AU'),pathlib.Path(folder),datetime(2026,11,8,5,tzinfo=timezone.utc))
            self.assertEqual(rows,[])

    def test_historical_different_station_names_are_not_automatic_aliases(self):
        data=b'id,name,alt_names,country,closed,replaced_by\nSonyTen3.in,Sony Sports Ten 3,Ten Cricket,IN,,\n'
        _,aliases=epg.official_directory(data)
        self.assertNotIn(('tencricket','IN'),aliases)

    def test_saved_station_bindings_keep_their_original_source_and_exact_id(self):
        self.assertEqual(epg.saved_feed('US2'),'share_US2')
        self.assertEqual(epg.saved_feed('GH:share_US2'),'share_US2')
        self.assertEqual(epg.saved_feed('UK1'),'share_UK1')
        self.assertEqual(epg.saved_feed('AU1'),'share_AU1')
        self.assertEqual(epg.saved_feed('MX1'),'share_MX1')
        self.assertIsNone(epg.saved_feed('unknown'))

    def test_uk_directory_and_feed_suffix_match_gb_hints_without_changing_ids(self):
        official,aliases=epg.official_directory(b'id,name,alt_names,country,closed,replaced_by\nMUTV.uk,MUTV,,UK,,\n')
        feed={'id':'MUTV.uk','names':['MUTV UK'],'country':'GB',
              'feed':'share_UK1','programmes':[{'start':1}]}
        index=epg.candidate_index([feed],official,aliases)
        selected,_=epg.propose_binding({'name':'MUTV UK'},index,official,aliases)
        self.assertEqual(selected['id'],'MUTV.uk')
        self.assertEqual(selected['country'],'GB')
        self.assertIsNone(epg.propose_binding({'name':'MUTV Australia'},index,official,aliases)[0])

    def test_bein_english_service_uses_only_the_numbered_published_english_station(self):
        with tempfile.TemporaryDirectory() as folder:
            data='<tv>'
            for service in ('1_ENGLISH_Digital_Mono_EN','1_ENGLISH_Digital_Mono_AR','1_DIGITAL_Mono_EN'):
                identity='beIN_SPORTS'+service+'.bein'
                data+=f'<channel id="{identity}"><display-name>{identity[:-5]}</display-name></channel>'
                data+=f'<programme channel="{identity}" start="20261108050000 +0000" stop="20261108080000 +0000"><title>Live football</title></programme>'
            data+='</tv>'
            with gzip.open(pathlib.Path(folder)/'share_BEIN1.xml.gz','wb') as output:output.write(data.encode())
            rows=epg.read_feed(('share_BEIN1','https://example.invalid/guide.xml.gz','QA'),pathlib.Path(folder),datetime(2026,11,8,6,tzinfo=timezone.utc))
            official,aliases=epg.official_directory(b'id,name,alt_names,country,closed,replaced_by\nbeINSportsEnglish1.qa,beIN Sports English 1,,QA,,\n')
            index=epg.candidate_index(rows,official,aliases)
            selected,_=epg.propose_binding({'name':'beIN ENGLISH 1'},index,official,aliases)
            self.assertEqual(selected['id'],'beIN_SPORTS1_ENGLISH_Digital_Mono_EN.bein')
            self.assertEqual(selected['names'][0],'beIN_SPORTS1_ENGLISH_Digital_Mono_EN')
            self.assertIsNone(epg.propose_binding({'name':'beIN ENGLISH'},index,official,aliases)[0])

if __name__=='__main__':unittest.main()
