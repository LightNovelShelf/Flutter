CMAKE ?= cmake
ANDROID_NDK_HOME ?= $(ANDROID_NDK_ROOT)
ANDROID_PLATFORM ?= android-23
ANDROID_ABIS := armeabi-v7a arm64-v8a x86_64

.PHONY: android macos ios clean

android: $(addprefix android-,$(ANDROID_ABIS))

android-%:
	@test -n "$(ANDROID_NDK_HOME)" || (echo "ANDROID_NDK_HOME is required" >&2; exit 1)
	$(CMAKE) -S . -B build/android-$* -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_TOOLCHAIN_FILE=$(ANDROID_NDK_HOME)/build/cmake/android.toolchain.cmake \
		-DANDROID_ABI=$* \
		-DANDROID_PLATFORM=$(ANDROID_PLATFORM) \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/android/$*)
	$(CMAKE) --build build/android-$* --parallel

macos:
	$(CMAKE) -S . -B build/macos-arm64 -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/macos/arm64)
	$(CMAKE) --build build/macos-arm64 --parallel
	$(CMAKE) -S . -B build/macos-x64 -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=x86_64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/macos/x64)
	$(CMAKE) --build build/macos-x64 --parallel

ios:
	$(CMAKE) -S . -B build/ios-device -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=iphoneos \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/ios/iphoneos-arm64)
	$(CMAKE) --build build/ios-device --parallel
	$(CMAKE) -S . -B build/ios-simulator-arm64 -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=iphonesimulator \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/ios/iphonesimulator-arm64)
	$(CMAKE) --build build/ios-simulator-arm64 --parallel
	$(CMAKE) -S . -B build/ios-simulator-x64 -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=iphonesimulator \
		-DCMAKE_OSX_ARCHITECTURES=x86_64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
		-DLN_OUTPUT_DIR=$(abspath prebuilt/ios/iphonesimulator-x64)
	$(CMAKE) --build build/ios-simulator-x64 --parallel

clean:
	$(CMAKE) -E remove_directory build
