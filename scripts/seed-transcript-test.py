"""Seed only the booted simulator with a synthetic speech/transcript UI fixture."""
import subprocess, json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
container = Path(subprocess.check_output(['xcrun','simctl','get_app_container','booted','com.zinger.quickrecord','data'],text=True).strip())
folder = container/'Documents/Recordings'
folder.mkdir(parents=True,exist_ok=True)
audio = folder/'transcript-ui-fixture.m4a'
subprocess.run(['afconvert','-f','m4af','-d','aac',str(root/'QuickRecordTests/chinese-sample.aiff'),str(audio)],check=True)
text = '文字界面测试。今天下午三点开会，请带上电脑。'
audio.with_suffix('.txt').write_text(text)
audio.with_suffix('.transcript.json').write_text(json.dumps({'status':'complete','text':text,'detail':'文字已保存 · TXT 已生成','language':'zh-CN','updatedAt':812000000},ensure_ascii=False))
print('Synthetic fixture added to simulator only.')
