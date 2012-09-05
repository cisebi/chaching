# Build

**Note:** This folder of scripts must be in your Xcode project directory.

This is a customizable Jenkins build script that will allow you to:

+ Build the project
+ Run unit tests (if you have a target that uses the UnitTestRunner framework)
+ Generate an IPA for App Store / enterprise distribution

Usage
==

	usage: ./build.sh [options]
	
		-b builds the project
		-t runs unit tests
		-m makes an ipa for the project
		
		providing no switches will run all methods

**Note:** Make sure to set the bundle identifier variables and your project name in CONFIG.sh.

If you wish to customize build.sh, all modifications should be done in build() unit_test() and make()

If you plan on building for enterprise and distribution you should customize the methods as follows:

	if [ $USER == enterprise ]; then
		...
	elif [ $USER == distribution ]; then
		...
	fi

Sample implementations are already in place.

Jenkins
==

On your Jenkins job simply put in the Execute Shell box:

	security unlock -p tester123
	./path/to/xcode/project/directory/scripts/build.sh


