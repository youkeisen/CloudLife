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
    // 有些插件（file_picker）自己声明按 android-34 编译，但它依赖的
    // flutter_plugin_android_lifecycle 要求使用方 compileSdk >= 36。
    // 这里统一把所有插件子项目的 compileSdk 抬到 36，避免 CheckAarMetadata 报错。
    // 注意：必须注册在 evaluationDependsOn 之前，晚了会报「already evaluated」。
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
            ?: return@afterEvaluate
        try {
            (androidExt as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(36)
        } catch (_: Throwable) {
            // 不支持的类型就跳过，让它按原来的编
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
