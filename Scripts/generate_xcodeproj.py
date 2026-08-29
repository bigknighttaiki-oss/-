#!/usr/bin/env python3
"""MacBackup.xcodeproj/project.pbxproj を生成する。

Xcode プロジェクトファイルを手で編集すると壊れやすいので、
ファイルを追加・削除したらこのスクリプトを再実行して作り直す:

    python3 Scripts/generate_xcodeproj.py

XcodeGen を使う場合は project.yml があるのでそちらでもよい。
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_ROOT = "MacBackup"
PROJECT_NAME = "MacBackup"
BUNDLE_ID = "com.example.MacBackup"
DEPLOYMENT_TARGET = "13.0"
SWIFT_VERSION = "5.9"


def oid(*parts):
    """パスから決定的に 24 桁の識別子を作る。"""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def write_scheme(out_dir, target_id):
    """共有スキームを書き出す。

    スキームが無いと `xcodebuild -scheme` が使えず、CI でビルドできない。
    Xcode がローカルに作るスキームはユーザー固有で共有されないため、
    プロジェクトと一緒に生成して追跡する。
    """
    reference = (
        '<BuildableReference\n'
        '               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{target_id}"\n'
        f'               BuildableName = "{PROJECT_NAME}.app"\n'
        f'               BlueprintName = "{PROJECT_NAME}"\n'
        f'               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">\n'
        '            </BuildableReference>'
    )
    scheme_dir = os.path.join(out_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    path = os.path.join(scheme_dir, f"{PROJECT_NAME}.xcscheme")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(SCHEME_TEMPLATE.format(reference=reference))
    return path



def collect():
    """ソースツリーを走査して {ディレクトリ: [ファイル]} を返す。"""
    tree = {}
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, SOURCE_ROOT)):
        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, ROOT)
        keep = sorted(
            f for f in filenames
            if f.endswith((".swift", ".plist", ".entitlements")) and not f.startswith(".")
        )
        tree[rel_dir] = (sorted(dirnames), keep)
    return tree


def main():
    tree = collect()

    swift_files = []   # (path, file_ref_id, build_file_id)
    other_files = []   # (path, file_ref_id)
    for rel_dir, (_, filenames) in sorted(tree.items()):
        for name in filenames:
            path = os.path.join(rel_dir, name)
            if name.endswith(".swift"):
                swift_files.append((path, oid("ref", path), oid("build", path)))
            else:
                other_files.append((path, oid("ref", path)))

    lines = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")

    # PBXBuildFile
    add("\n/* Begin PBXBuildFile section */")
    for path, ref, build in swift_files:
        name = os.path.basename(path)
        add(f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    add("/* End PBXBuildFile section */")

    # PBXFileReference
    add("\n/* Begin PBXFileReference section */")
    product_ref = oid("product")
    add(f'\t\t{product_ref} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{PROJECT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    for path, ref, _ in swift_files:
        name = os.path.basename(path)
        add(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};')
    for path, ref in other_files:
        name = os.path.basename(path)
        kind = "text.plist.entitlements" if name.endswith(".entitlements") else "text.plist.xml"
        add(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = "{name}"; sourceTree = "<group>"; }};')
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    frameworks_phase = oid("frameworks")
    add("\n/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    main_group = oid("group", "<main>")
    products_group = oid("group", "<products>")
    add("\n/* Begin PBXGroup section */")

    def group_children(rel_dir):
        subdirs, filenames = tree[rel_dir]
        children = []
        for sub in subdirs:
            sub_rel = os.path.join(rel_dir, sub)
            children.append((oid("group", sub_rel), sub))
        for name in filenames:
            children.append((oid("ref", os.path.join(rel_dir, name)), name))
        return children

    for rel_dir in sorted(tree):
        gid = oid("group", rel_dir)
        add(f"\t\t{gid} /* {os.path.basename(rel_dir)} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child_id, child_name in group_children(rel_dir):
            add(f"\t\t\t\t{child_id} /* {child_name} */,")
        add("\t\t\t);")
        add(f'\t\t\tpath = "{os.path.basename(rel_dir)}";')
        add('\t\t\tsourceTree = "<group>";')
        add("\t\t};")

    add(f"\t\t{main_group} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{oid('group', SOURCE_ROOT)} /* {SOURCE_ROOT} */,")
    add(f"\t\t\t\t{products_group} /* Products */,")
    add("\t\t\t);")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")
    add(f"\t\t{products_group} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{product_ref} /* {PROJECT_NAME}.app */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add('\t\t\tsourceTree = "<group>";')
    add("\t\t};")
    add("/* End PBXGroup section */")

    # PBXNativeTarget
    target_id = oid("target")
    sources_phase = oid("sources")
    resources_phase = oid("resources")
    target_config_list = oid("configlist", "target")
    project_config_list = oid("configlist", "project")
    project_id = oid("project")

    add("\n/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_id} /* {PROJECT_NAME} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;")
    add("\t\t\tbuildPhases = (")
    add(f"\t\t\t\t{sources_phase} /* Sources */,")
    add(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    add(f"\t\t\t\t{resources_phase} /* Resources */,")
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add(f'\t\t\tname = "{PROJECT_NAME}";')
    add(f'\t\t\tproductName = "{PROJECT_NAME}";')
    add(f"\t\t\tproductReference = {product_ref} /* {PROJECT_NAME}.app */;")
    add('\t\t\tproductType = "com.apple.product-type.application";')
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # PBXProject
    add("\n/* Begin PBXProject section */")
    add(f"\t\t{project_id} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t\tTargetAttributes = {")
    add(f"\t\t\t\t\t{target_id} = {{")
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = ja;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\tja,")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {main_group};")
    add(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    add('\t\t\tprojectDirPath = "";')
    add('\t\t\tprojectRoot = "";')
    add("\t\t\ttargets = (")
    add(f"\t\t\t\t{target_id} /* {PROJECT_NAME} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("\n/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_phase} /* Resources */ = {{")
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    add("\n/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase} /* Sources */ = {{")
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for path, _, build in swift_files:
        add(f"\t\t\t\t{build} /* {os.path.basename(path)} in Sources */,")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # XCBuildConfiguration
    project_debug = oid("config", "project", "Debug")
    project_release = oid("config", "project", "Release")
    target_debug = oid("config", "target", "Debug")
    target_release = oid("config", "target", "Release")

    common_project_settings = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_OBJC_WEAK = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        f"MACOSX_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};",
        "SDKROOT = macosx;",
        f"SWIFT_VERSION = {SWIFT_VERSION};",
    ]
    common_target_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "CODE_SIGN_ENTITLEMENTS = MacBackup/Resources/MacBackup.entitlements;",
        "CODE_SIGN_STYLE = Automatic;",
        "COMBINE_HIDPI_IMAGES = YES;",
        "CURRENT_PROJECT_VERSION = 1;",
        "ENABLE_HARDENED_RUNTIME = YES;",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = MacBackup/Resources/Info.plist;",
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");',
        "MARKETING_VERSION = 0.1.0;",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        "SWIFT_EMIT_LOC_STRINGS = YES;",
    ]

    def config_block(cid, name, settings):
        add(f"\t\t{cid} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for setting in settings:
            add(f"\t\t\t\t{setting}")
        add("\t\t\t};")
        add(f'\t\t\tname = {name};')
        add("\t\t};")

    add("\n/* Begin XCBuildConfiguration section */")
    config_block(project_debug, "Debug", common_project_settings + [
        "DEBUG_INFORMATION_FORMAT = dwarf;",
        "ENABLE_TESTABILITY = YES;",
        "GCC_OPTIMIZATION_LEVEL = 0;",
        'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
        "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
        "ONLY_ACTIVE_ARCH = YES;",
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";',
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    ])
    config_block(project_release, "Release", common_project_settings + [
        'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
        "ENABLE_NS_ASSERTIONS = NO;",
        "MTL_ENABLE_DEBUG_INFO = NO;",
        "SWIFT_COMPILATION_MODE = wholemodule;",
        "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
    ])
    config_block(target_debug, "Debug", common_target_settings)
    config_block(target_release, "Release", common_target_settings)
    add("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    add("\n/* Begin XCConfigurationList section */")
    for list_id, label, debug_id, release_id in (
        (project_config_list, f'PBXProject "{PROJECT_NAME}"', project_debug, project_release),
        (target_config_list, f'PBXNativeTarget "{PROJECT_NAME}"', target_debug, target_release),
    ):
        add(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        add(f"\t\t\t\t{debug_id} /* Debug */,")
        add(f"\t\t\t\t{release_id} /* Release */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {project_id} /* Project object */;")
    add("}")

    out_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    scheme_path = write_scheme(out_dir, target_id)
    print(f"生成しました: {out_dir}/project.pbxproj ({len(swift_files)} Swift files)")
    print(f"生成しました: {scheme_path}")


if __name__ == "__main__":
    main()
