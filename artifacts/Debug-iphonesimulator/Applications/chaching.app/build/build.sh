#!/bin/bash
# This is a highly customizable jenkins build script
# designed to work with most projects out of the box.
#
# For a simple setup. Just set the PROJECT_NAME and
# BUNDLE_ID variables below.
#
# The project that this script is a part of is hosted at
# https://git.soma.salesforce.com/iOS/build
#
# Accepts four switches
# -h help
# -b build the project
# -t run unit tests
# -m make an ipa for the project
#
# No switches will run all methods
#
# All switches can be customized in their methods at the bottom of this file

declare readonly CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

declare readonly PROJECT_DIR="`dirname "$CURRENT_DIR"`"

source "$CURRENT_DIR/CONFIG.sh"

declare readonly TARGET="$PROJECT_NAME"
declare readonly TEST_TARGET="${PROJECT_NAME}Tests"

if [ -z "$WORKSPACE" ]; then
    declare readonly ARTIFACTS="$PROJECT_DIR/artifacts"
else
    declare readonly ARTIFACTS="$WORKSPACE/artifacts"
fi

declare readonly OUTPUT="$ARTIFACTS/output.txt"

declare readonly PHONE_SDK=iphoneos
declare readonly SIMULATOR_SDK=iphonesimulator

declare readonly APPSTORE_PREFIX="62J96EUJ9N" # 'salesforce.com'. Team Agent is Jason Schroeder <jschroeder@salesforce.com>
declare readonly ENTERPRISE_PREFIX="4PZ44KB26X" # 'Salesforce.com'. Team Agent is Darrell Gillmeister <dgillmeister@salesforce.com>

declare readonly APPSTORE_SUFFIX="AppStore"
declare readonly ENTERPRISE_SUFFIX="Internal"
declare readonly DEV_SUFFIX="Dev"

declare readonly INFO_PLIST="$PROJECT_DIR/$PROJECT_NAME/${PROJECT_NAME}-Info.plist"

# Echoes the profile path of a mobile provisioning profile
function get_profile_path() {
	local prefix="$1"; shift
	local bundle="$1"; shift
	local suffix="$1"; shift
	echo "$HOME/Library/MobileDevice/Provisioning Profiles/$prefix.${bundle}_$suffix.mobileprovision"
}

declare readonly APPSTORE_PROFILE="`get_profile_path $APPSTORE_PREFIX $APPSTORE_BUNDLE_ID $APPSTORE_SUFFIX`"
declare readonly DEV_PROFILE="`get_profile_path $APPSTORE_PREFIX $APPSTORE_BUNDLE_ID $DEV_SUFFIX`"
declare readonly ENTERPRISE_PROFILE="`get_profile_path $ENTERPRISE_PREFIX $ENTERPRISE_BUNDLE_ID $ENTERPRISE_SUFFIX`"

function usage() {
	echo "usage: ./build.sh [options]"
	echo ""
	echo "	-b builds the project"
	echo "	-t runs unit tests (requires you to be using the UnitTestRunner framework)"
	echo "	-m makes an ipa for the project"
	echo ""
	echo "	providing no switches will run all methods"
	echo ""
}

function clean() {
	rm -rf "$ARTIFACTS"
	mkdir "$ARTIFACTS"
}

# @method set_bundle_identifier:
# @abstract sets the bundle identifier in the project's Info.plist file
# @param $1 the bundle identifier (com.salesforce.example)
function set_bundle_identifier() {
	local identifier="$1"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $1" "$INFO_PLIST"
}

# @method build_helper:
# @abstract clean and install an Xcode project
# @param $1 - project
# @param $2 - target
# @param $3 - configuration (e.g. Release, Debug)
# @param $4 - sdk
# Optional arguments (must come last)
# @switch -n do not archive dSYM files
# @switch -b <bundle id> bundle identifier
# @switch -i <path> install root
# @switch -c <file> xcconfig file
function build_helper() {
	local project="$1"; shift
	local target="$1"; shift
	local configuration="$1"; shift
	local sdk="$1"; shift
	local archive=1
	local bundle_prefix=
	local install_root=
	local config=
	
	unset OPTIND
	while getopts "nb:i:c:" opt; do
		case $opt in
			n ) archive=0;;
			b ) bundle_prefix="$OPTARG";;
			i ) install_root="$OPTARG";;
			c ) config="$OPTARG";;
		esac
	done
	
	if [ ! -z bundle_prefix ]; then
		set_bundle_identifier $bundle_prefix
	fi
	
	if [ -z "$install_root" ]; then
		install_root="$ARTIFACTS/$configuration-$sdk"
	fi
	
	if [ ! -z "$config" ]; then
		config="-xcconfig \"$config\""
	fi
	
	eval "xcodebuild -project \"$PROJECT_DIR/$project.xcodeproj\" -target \"$target\" -configuration \"$configuration\" \
				-sdk \"$sdk\" $config INSTALL_ROOT=\"$install_root\" DWARF_DSYM_FOLDER_PATH=\"$install_root\" clean"
	eval "xcodebuild -project \"$PROJECT_DIR/$project.xcodeproj\" -target \"$target\" -configuration \"$configuration\" \
				-sdk \"$sdk\" $config INSTALL_ROOT=\"$install_root\" DWARF_DSYM_FOLDER_PATH=\"$install_root\" install"
	
	if [ $archive == 1 ]; then
		cd "$install_root"
		zip -qr $configuration-$sdk-dSYMs *.dSYM
		mv $configuration-$sdk-dSYMs.zip "$ARTIFACTS"
	fi
}

# @method run_unit_tests:
# @abstract builds a target that has the UnitTestRunner framework and runs the unit tests
# @dependency requires RunIPhoneLaunchDaemons.sh to be in the same directory
function run_unit_tests() {
	local install_dir="$ARTIFACTS/UnitTests"
	
	build_helper "$PROJECT_NAME" "$TEST_TARGET" "Debug" "$SIMULATOR_SDK" -i "$install_dir" -n
	
    local simulator_dir=`xcodebuild -version -sdk iphonesimulator Path`
    local executable="$install_dir/Applications/${PROJECT_NAME}Tests.app/${PROJECT_NAME}Tests"

	local temp_dir=`mktemp -d -t unittests`

    local report_dir="$ARTIFACTS/UnitTestsReports"
    mkdir "$report_dir"

    export DYLD_ROOT_PATH="$simulator_dir"
    export IPHONE_SIMULATOR_ROOT="$simulator_dir"
    export CFFIXED_USER_HOME="$temp_dir"
    export UNIT_TEST_APP="$executable"

    (
    launchctl submit -l RunIPhoneLaunchDaemons -- "$CURRENT_DIR/RunIPhoneLaunchDaemons.sh" "$IPHONE_SIMULATOR_ROOT" "$CFFIXED_USER_HOME"
    trap "launchctl remove RunIPhoneLaunchDaemons" INT TERM EXIT
    "$UNIT_TEST_APP" -RegisterForSystemEvents -AutoRun > /dev/null 2>&1
    )

    cp -R "$temp_dir/Documents/test-reports/" "$report_dir/"

    rm -rf "$install_dir"
}

# @method make_helper:
# @abstract generates an ipa from from a .app directory:
# @param $1 - path to put the ipa
# @param $2 - path of the provisioning profile to be embedded
function make_helper() {
	local app="$1"; shift
	local profile="$1"; shift
	xcrun -sdk iphoneos PackageApplication -v "$app" -o "$ARTIFACTS/$PROJECT_NAME.ipa" --sign "iPhone Distribution" --embed "$profile"
}

# @method build:
# @abstract build phase fired by the -b switch
function build() {
	if [ $USER == enterprise ]; then
		build_helper "$PROJECT_NAME" "$TARGET" "Release" "$PHONE_SDK" -c "$CURRENT_DIR/enterprise.xcconfig" -b $ENTERPRISE_BUNDLE_ID
	elif [ $USER == distribution ]; then
		build_helper "$PROJECT_NAME" "$TARGET" "Release" "$PHONE_SDK" -c "$CURRENT_DIR/distribution.xcconfig" -b $APPSTORE_BUNDLE_ID
	else # building locally
		build_helper "$PROJECT_NAME" "$TARGET" "Debug" "$SIMULATOR_SDK"
	fi
}

# @method unit_test:
# @abstract test phase fired by the -t switch
function unit_test() {
	run_unit_tests
}

# @method make:
# @abstract make phase fired by the -m switch
function make() {
	if [ $USER == enterprise ]; then
		make_helper "$ARTIFACTS/Release-iphoneos/Applications/$PROJECT_NAME.app" "$ENTERPRISE_PROFILE"
	elif [ $USER == distribution ]; then
		make_helper "$ARTIFACTS/Release-iphoneos/Applications/$PROJECT_NAME.app" "$APPSTORE_PROFILE"
	fi
}

function main() {
	local usage=0
	local build=0
	local unit_test=0
	local make=0
	
	unset OPTIND
	while getopts "hbtmp" opt; do
		case $opt in
			h  ) usage=1;;
			b  ) build=1;;
			t  ) unit_test=1;;
			m  ) make=1;;
			\? ) echo "Invalid switch. Use -h for help."; exit 1;;
		esac
	done
	
	if [ $usage == 1 ]; then
		usage
		exit 1
	fi
	
	if [ $OPTIND == 1 ]; then
		build=1; unit_test=1; make=1
	fi
	
	clean
	if [ $build == 1 ]; 	then build; fi
	if [ $unit_test == 1 ]; then unit_test; fi
	if [ $make == 1 ]; 		then make; fi
}

set -e

main "$@"