"""Fail when shipped controls/options have no acceptance case.

This checks coverage of the plan, not execution of the browser interactions.
"""
import csv
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
MODEL='AX5'if(ROOT/'ui/index.html').exists()else'K2P'
HTML=ROOT/('ui/index.html'if MODEL=='AX5'else'payload/ui/index.html')

class Controls(HTMLParser):
    def __init__(self):super().__init__();self.controls=[];self.stack=[]
    def handle_starttag(self,tag,attrs):
        item=(tag,dict(attrs));parents=self.stack[:]
        if tag in ('button','input','select','textarea','summary','option','a'):self.controls.append((item,parents))
        if tag not in ('input','img','br','hr','meta','link'):self.stack.append(item)
    def handle_endtag(self,tag):
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0]==tag:self.stack=self.stack[:i];break

class ControlCoverage(unittest.TestCase):
    def test_every_static_control_and_option_has_steps_and_expected_result(self):
        with (ROOT/'docs/CONTROL_TEST_CASES.csv').open(encoding='utf-8-sig',newline='')as f:
            rows=[r for r in csv.DictReader(f)if r['机型']==MODEL]
        keys={r['控件定位']for r in rows};parser=Controls();parser.feed(HTML.read_text())
        recovery=ROOT/('ui/recovery.js' if MODEL=='AX5' else 'payload/padavan/recovery.js')
        template=recovery.read_text().split('dialog.innerHTML=`',1)[1].split('`;',1)[0]
        parser.feed(template)
        count=0;options=0;summaries=0
        for (tag,attrs),parents in parser.controls:
            if tag=='summary':summaries+=1;continue
            if tag=='option':
                identity=next(a.get('id')for t,a in reversed(parents)if t=='select')
                self.assertIn(identity+'='+attrs.get('value',''),keys);options+=1;continue
            identity=attrs.get('id')
            if not identity and tag=='button':
                form=next(a.get('id')for t,a in reversed(parents)if t=='form')
                identity={'policy-add':'policy-add-submit','inspect-search-form':'inspect-search-submit'}[form]
            self.assertIn(identity,keys,identity);count+=1
        self.assertEqual(count,len([r for r in rows if '-CTRL-'in r['用例ID']and r['类型']!='summary']))
        self.assertEqual(summaries,len([r for r in rows if r['类型']=='summary']))
        self.assertEqual(options,len([r for r in rows if r['类型']=='option']))
        for row in rows:
            for field in ['前置条件','操作步骤','预期结果','异常/边界','验证证据','恢复步骤']:
                self.assertTrue(row[field].strip(),(row['用例ID'],field))
    def test_desktop_and_mobile_results_are_explicit(self):
        with(ROOT/'docs/CONTROL_TEST_CASES.csv').open(encoding='utf-8-sig',newline='')as f:cases=list(csv.DictReader(f))
        with(ROOT/'docs/CONTROL_TEST_RESULTS.csv').open(encoding='utf-8-sig',newline='')as f:results=list(csv.DictReader(f))
        keys=[(r['用例ID'],r['端'])for r in results];self.assertEqual(len(keys),len(set(keys)))
        self.assertEqual(set(keys),{(r['用例ID'],surface)for r in cases for surface in ['桌面','手机窄屏']})
        for row in results:
            if row['状态']in ['实机页面通过','实机后端通过','自动测试通过']:
                self.assertTrue(row['证据']);self.assertTrue(row['实际结果'])

if __name__=='__main__':unittest.main()
