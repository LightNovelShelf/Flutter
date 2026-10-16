allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 插件模块默认用各自的 compileSdk、Flutter 默认 NDK 和 AGP 默认的 build-tools/CMake，统一到与 app 相同的版本，本机 SDK 每样只需装一份。
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.apply {
            compileSdk = 37
            buildToolsVersion = "37.0.0"
            ndkVersion = "30.0.16248370"
            // jni 插件带 C 代码，未指定 CMake 版本时会用 AGP 默认的 3.22.1。
            if (externalNativeBuild.cmake.path != null) externalNativeBuild.cmake.version = "4.1.2"
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
