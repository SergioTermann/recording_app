"""Add shared iOS files and a native macOS target to the existing small Xcode project."""
from pathlib import Path
import hashlib,plistlib
root=Path(__file__).resolve().parent.parent
p=root/'QuickRecord.xcodeproj/project.pbxproj';s=p.read_text()
def uid(v):return hashlib.sha1(v.encode()).hexdigest()[:24].upper()
shared=['Shared/RecordingModel.swift','Shared/ArchiveCore.swift','Shared/LocalTransport.swift']
ios=shared+['QuickRecord/MacArchiveSync.swift']
mac=shared+['QuickRecord/RecordingFolders.swift','QuickRecord/Transcription.swift','QuickRecord/DailySummary.swift','QuickRecord/DailySummaryAI.swift','GlimpseMac/MarkdownSupport.swift','GlimpseMac/MarkdownEditor.swift','GlimpseMac/MacLibrary.swift','GlimpseMac/MacSyncServer.swift','GlimpseMac/MacContentView.swift','GlimpseMac/GlimpseMacApp.swift']
objects=[];refs={};iosbuild=[];macbuild=[]
for path in sorted(set(ios+mac)):
 ref=uid('mac-ref-'+path);refs[path]=ref
 objects.append(f'{ref} = {{ isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT; }};')
 for target,files,builds in [('ios',ios,iosbuild),('mac',mac,macbuild)]:
  if path in files:
   build=uid(target+'-build-'+path);builds.append(build);objects.append(f'{build} = {{ isa = PBXBuildFile; fileRef = {ref}; }};')
group=uid('mac-shared-group');target=uid('glimpse-mac-target');product=uid('glimpse-mac-product');sources=uid('glimpse-mac-sources');resources=uid('glimpse-mac-resources');frameworks=uid('glimpse-mac-frameworks');configs=uid('glimpse-mac-configs');debug=uid('glimpse-mac-debug');release=uid('glimpse-mac-release');icon=uid('glimpse-mac-icon');iconbuild=uid('glimpse-mac-iconbuild')
objects += [f'{icon} = {{ isa = PBXFileReference; lastKnownFileType = image.icns; path = GlimpseMac/Glimpse.icns; sourceTree = SOURCE_ROOT; }};',f'{iconbuild} = {{ isa = PBXBuildFile; fileRef = {icon}; }};',f'{group} = {{ isa = PBXGroup; name = "Mac and Shared"; children = ({", ".join(refs.values())}, {icon}); sourceTree = "<group>"; }};',f'{product} = {{ isa = PBXFileReference; explicitFileType = wrapper.application; path = Glimpse.app; sourceTree = BUILT_PRODUCTS_DIR; }};',f'{sources} = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(macbuild)}); runOnlyForDeploymentPostprocessing = 0; }};',f'{resources} = {{ isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild}); runOnlyForDeploymentPostprocessing = 0; }};',f'{frameworks} = {{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};']
for name,cid in [('Debug',debug),('Release',release)]:
 objects.append(f'{cid} = {{ isa = XCBuildConfiguration; buildSettings = {{ SWIFT_ACTIVE_COMPILATION_CONDITIONS = {"DEBUG" if name == "Debug" else "RELEASE"}; SDKROOT = macosx; SUPPORTED_PLATFORMS = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; PRODUCT_BUNDLE_IDENTIFIER = com.zinger.glimpse.mac; PRODUCT_NAME = Glimpse; INFOPLIST_FILE = GlimpseMac/Info.plist; CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = GlimpseMac/Glimpse.entitlements; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES; GENERATE_INFOPLIST_FILE = NO; }}; name = {name}; }};')
objects += [f'{configs} = {{ isa = XCConfigurationList; buildConfigurations = ({debug}, {release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};',f'{target} = {{ isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = ({sources}, {frameworks}, {resources}); buildRules = (); dependencies = (); name = GlimpseMac; productName = Glimpse; productReference = {product}; productType = "com.apple.product-type.application"; }};']
if target not in s:
 s=s.replace('objects = {','objects = {\n'+'\n'.join(objects),1)
 s=s.replace('64292B1C2B2E13EAD8788FC8 = { isa = PBXGroup; children = (',f'64292B1C2B2E13EAD8788FC8 = {{ isa = PBXGroup; children = ({group}, ',1)
 s=s.replace('FBDC4F23F93125BBEEAE800C = { isa = PBXGroup; children = (',f'FBDC4F23F93125BBEEAE800C = {{ isa = PBXGroup; children = ({product}, ',1)
 s=s.replace('D3C3E067FC1BBCCEAA4D9313 = { isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (','D3C3E067FC1BBCCEAA4D9313 = { isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(iosbuild)+', ',1)
 s=s.replace('targets = (4B3262DAA45B769FFB5A6DEA',f'targets = ({target}, 4B3262DAA45B769FFB5A6DEA',1)
 p.write_text(s)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Glimpse.app" BlueprintName="GlimpseMac" ReferencedContainer="container:QuickRecord.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Glimpse.app" BlueprintName="GlimpseMac" ReferencedContainer="container:QuickRecord.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'QuickRecord.xcodeproj/xcshareddata/xcschemes/GlimpseMac.xcscheme').write_text(scheme)
info=dict(CFBundleDevelopmentRegion='zh_CN',CFBundleDisplayName='Glimpse',CFBundleName='Glimpse',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundlePackageType='APPL',CFBundleShortVersionString='1.0',CFBundleVersion='1',CFBundleIconFile='Glimpse',LSMinimumSystemVersion='$(MACOSX_DEPLOYMENT_TARGET)',NSPrincipalClass='NSApplication',NSHighResolutionCapable=True,NSMicrophoneUsageDescription='Glimpse 使用 Mac 的麦克风录制生活记录和灵感。',NSSpeechRecognitionUsageDescription='Glimpse 将录音在本机转换为文字并保存 TXT。',NSLocalNetworkUsageDescription='在同一 Wi-Fi 下接收已配对 iPhone 的录音和文字进行归档。',NSBonjourServices=['_glimpse-sync._tcp'])
if not (root/'GlimpseMac/Info.plist').exists():
 (root/'GlimpseMac/Info.plist').write_bytes(plistlib.dumps(info,sort_keys=False))
(root/'GlimpseMac/Glimpse.entitlements').write_bytes(plistlib.dumps({'com.apple.security.device.audio-input':True}))
print('Native macOS target and iOS shared sources configured.')
