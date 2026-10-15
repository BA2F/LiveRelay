allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // integration_test 插件声明了动态版本依赖（runner/rules/espresso-core），
    // 解析时需联网列 Maven 版本；钉到本地已解析过的版本，无网络时也能构建。
    configurations.all {
        resolutionStrategy.force(
            "androidx.test:runner:1.3.0",
            "androidx.test:rules:1.2.0",
            "androidx.test.espresso:espresso-core:3.3.0",
        )
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
