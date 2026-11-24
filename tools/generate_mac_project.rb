#!/usr/bin/env ruby
# frozen_string_literal: true

# Mac の入力メソッドのプロジェクト(MacInputMethod/EcrituPourMac.xcodeproj)を作り直す。
# 正はこのスクリプトで、生成物の pbxproj は手で直さない。iOS のプロジェクト(écritu.xcodeproj)には触れない。
# 使い方: ruby tools/generate_mac_project.rb(xcodeproj gem 1.27.0)
#
# 生成するもの:
# - ターゲット EcrituPourMac(macOS アプリ。製品名 ecritu)と EcrituPourMacTests(ホストアプリ無しの単体テスト束)
# - ローカルの Swift パッケージ参照(Packages/EcrituConversion、Packages/EcrituInput)
# - Copy Bundle Resources(辞書の仮置き・初期語彙・grammaire.plist・アイコン)と、最後の辞書スクリプトのフェーズ
# - 共有 scheme EcrituPourMac(build と test)

require 'fileutils'
require 'xcodeproj'

ROOT_DIR = File.expand_path('..', __dir__)
MAC_DIR = File.join(ROOT_DIR, 'MacInputMethod')
PROJECT_PATH = File.join(MAC_DIR, 'EcrituPourMac.xcodeproj')
DEPLOYMENT_TARGET = '14.0'

APP_SOURCES = %w[
  main.swift
  EcrituInputController.swift
  KeyEventTranslator.swift
  CandidateWindow.swift
  ConversionService.swift
].freeze
# テスト束にも直接コンパイルする本体のファイル(アプリは main.swift を持つので @testable import しない)
SOURCES_SHARED_WITH_TESTS = %w[
  KeyEventTranslator.swift
  ConversionService.swift
].freeze
TEST_SOURCES = %w[
  ConversionServiceTests.swift
  KeyEventTranslatorTests.swift
  InfoPlistTests.swift
].freeze
ICON_FILE = 'ecritu.tiff'
INITIAL_VOCAB_FILES = %w[
  InitialAjoutVocabMigration.json
  InitialMiscVocabMigration.json
  InitialShortcutVocabMigration.json
  InitialSupprHiddenNounVocabMigration.json
  InitialSupprHiddenVocabMigration.json
  InitialSupprVocabMigration.json
].freeze
# 最後のビルドフェーズ。tmp/ の辞書を確かめ、バンドルの仮置きを本物で上書きする
DICTIONARY_SCRIPT = "bash \"$SRCROOT/../tools/refresh_simulator_dictionary_on_build.sh\"\n"

def add_local_package(project, relative_path)
  reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  reference.relative_path = relative_path
  project.root_object.package_references << reference
  reference
end

def link_package_product(project, target, package_reference, product_name)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package_reference
  dependency.product_name = product_name
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# 対象の構成の設定を、xcconfig の上に置く最小の値だけにする(gem の初期値は xcconfig より強いので残さない)
def configure_target(target, xcconfig_reference, settings)
  target.build_configurations.each do |configuration|
    configuration.base_configuration_reference = xcconfig_reference
    configuration.build_settings = settings.dup
  end
end

FileUtils.rm_rf(PROJECT_PATH)
# ローカルの Swift パッケージ参照(XCLocalSwiftPackageReference)は新しい形式でしか読まれないので、iOS のプロジェクトと同じ 77 にする
project = Xcodeproj::Project.new(PROJECT_PATH, false, 77)

# グループとファイルの参照
main_group = project.main_group
config_group = main_group.new_group('Config', 'Config')
xcconfig_reference = config_group.new_file('EcrituPourMac.xcconfig')

sources_group = main_group.new_group('Sources', 'Sources')
source_references = APP_SOURCES.to_h { |name| [name, sources_group.new_file(name)] }

tests_group = main_group.new_group('Tests', 'Tests')
test_references = TEST_SOURCES.map { |name| tests_group.new_file(name) }

resources_group = main_group.new_group('Resources', 'Resources')
resources_group.new_file('Info.plist')
icon_reference = resources_group.new_file(ICON_FILE)
# 入力ソースの一覧と入力メニューに出る名前(入力モードの ID → 表示名)。これが無いと一覧に ID のまま出る
info_strings_group = resources_group.new_variant_group('InfoPlist.strings')
%w[en ja].each do |language|
  reference = info_strings_group.new_file("#{language}.lproj/InfoPlist.strings")
  reference.name = language
end
project.root_object.known_regions = (project.root_object.known_regions + %w[en ja]).uniq

keyboard_group = main_group.new_group('KeyboardExtension', '../KeyboardExtension')
default_dictionary_group = keyboard_group.new_group('DefaultDictionaryResources', 'DefaultDictionaryResources')
# 仮置きは全部入れる。ファイル名はディレクトリーの実物から取る(É の正規化形を実ファイルと同じにするため)
default_dictionary_names = Dir.children(File.join(ROOT_DIR, 'KeyboardExtension', 'DefaultDictionaryResources'))
                              .reject { |name| name.start_with?('.') }
                              .sort
default_dictionary_references = default_dictionary_names.map { |name| default_dictionary_group.new_file(name) }
initial_vocab_references = INITIAL_VOCAB_FILES.map { |name| keyboard_group.new_file(name) }

references_group = main_group.new_group('references', '../references')
grammaire_reference = references_group.new_file('grammaire.plist')

resource_references = default_dictionary_references + initial_vocab_references + [grammaire_reference, icon_reference]

# パッケージ
conversion_package = add_local_package(project, '../Packages/EcrituConversion')
input_package = add_local_package(project, '../Packages/EcrituInput')

# アプリ
app = project.new_target(:application, 'EcrituPourMac', :osx, DEPLOYMENT_TARGET, nil, :swift, 'ecritu')
configure_target(app, xcconfig_reference, {
  'PRODUCT_NAME' => 'ecritu',
  'PRODUCT_BUNDLE_IDENTIFIER' => '$(ECRITU_MAC_BUNDLE_IDENTIFIER)',
  'INFOPLIST_FILE' => 'Resources/Info.plist',
  'GENERATE_INFOPLIST_FILE' => 'NO'
})
app.add_file_references(APP_SOURCES.map { |name| source_references[name] })
app.add_resources(resource_references + [info_strings_group])
link_package_product(project, app, conversion_package, 'EcrituConversion')
link_package_product(project, app, input_package, 'EcrituInput')

# テスト束(ホストアプリ無し)。Bundle(for: KanaKanjiStore.self) はテスト束を指すので、同じ資源と同じ辞書のフェーズを持つ
tests = project.new_target(:unit_test_bundle, 'EcrituPourMacTests', :osx, DEPLOYMENT_TARGET, nil, :swift, 'EcrituPourMacTests')
configure_target(tests, xcconfig_reference, {
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'PRODUCT_BUNDLE_IDENTIFIER' => '$(ECRITU_MAC_BUNDLE_IDENTIFIER).tests',
  'GENERATE_INFOPLIST_FILE' => 'YES'
})
tests.add_file_references(SOURCES_SHARED_WITH_TESTS.map { |name| source_references[name] } + test_references)
tests.add_resources(resource_references)
link_package_product(project, tests, conversion_package, 'EcrituConversion')
link_package_product(project, tests, input_package, 'EcrituInput')

# 最後のビルドフェーズ(Resources の後。毎回走らせる)
[app, tests].each do |target|
  phase = target.new_shell_script_build_phase('Refresh Dictionary Artifacts')
  phase.shell_script = DICTIONARY_SCRIPT
  phase.always_out_of_date = '1'
end

# 生成のたびに UUID が変わらないようにする
project.predictabilize_uuids
project.save

# 共有 scheme(build と test)
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(PROJECT_PATH, 'EcrituPourMac', true)

puts "generated #{PROJECT_PATH}"
