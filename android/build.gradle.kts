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
subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
// --- FIX LỖI NAMESPACE TRÊN GITHUB ACTIONS (PHIÊN BẢN KOTLIN DSL) ---
subprojects {
    // Thay vì dùng afterEvaluate, ta can thiệp trực tiếp vào plugin management
    plugins.withType<com.android.build.gradle.api.AndroidBasePlugin> {
        val android = extensions.getByType<com.android.build.gradle.BaseExtension>()
        // Fix riêng cho ota_update
        if (project.name == "ota_update") {
            android.namespace = "main.it.implicit.ota_update"
        }
        // Fix tổng quát cho bất kỳ plugin nào bị thiếu namespace
        if (android.namespace == null) {
            android.namespace = project.group.toString()
        }
    }
}
