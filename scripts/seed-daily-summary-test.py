"""Synthetic yesterday fixtures, only in the booted simulator; never touches a phone."""
from pathlib import Path
from datetime import datetime, timedelta
import subprocess
import json

root = Path(__file__).resolve().parent.parent
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', 'booted', 'com.zinger.quickrecord', 'data'], text=True).strip())
yesterday = datetime.now() - timedelta(days=1)
for category, text, hour in [('日常记录', '日报测试：今天去公园散步，心情很好。', 10), ('idea', '日报测试：想做一个植物浇水提醒工具，明天先画草图。', 18)]:
    folder = container / 'Documents/Recordings' / category
    folder.mkdir(parents=True, exist_ok=True)
    audio = folder / 'daily-summary-fixture.m4a'
    subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', str(root/'QuickRecordTests/chinese-sample.aiff'), str(audio)], check=True)
    stamp = yesterday.replace(hour=hour, minute=0, second=0).strftime('%m/%d/%Y %H:%M:%S')
    subprocess.run(['xcrun', 'SetFile', '-d', stamp, str(audio)], check=True)
    audio.with_suffix('.txt').write_text(text)
    audio.with_suffix('.transcript.json').write_text(json.dumps({'status': 'complete', 'text': text, 'detail': '文字已保存', 'language': 'zh-CN', 'updatedAt': 812000000}, ensure_ascii=False))
print('Seeded two synthetic yesterday recordings in simulator only.')
