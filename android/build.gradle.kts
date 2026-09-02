allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://download.flutter.io") }
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            force("androidx.activity:activity:1.9.3")
            force("androidx.activity:activity-ktx:1.9.3")
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
            force("androidx.lifecycle:lifecycle-common:2.8.7")
            force("androidx.lifecycle:lifecycle-runtime:2.8.7")
            force("androidx.lifecycle:lifecycle-viewmodel:2.8.7")
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    if (name == "flutter_pcm_player") {
        pluginManager.withPlugin("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                namespace = "com.example.flutter_pcm_player"
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")

    fun configureAndroid() {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            // Fix namespace
            try {
                val getNamespaceMethod = android.javaClass.getMethod("getNamespace")
                val setNamespaceMethod = android.javaClass.getMethod("setNamespace", String::class.java)
                val currentNamespace = getNamespaceMethod.invoke(android)
                if (currentNamespace == null) {
                    val packageName = "com.xiaozhi.${project.name.replace("-", "_").replace(":", "_")}"
                    setNamespaceMethod.invoke(android, packageName)
                    // Try to remove package from AndroidManifest.xml to avoid AGP 8+ error
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        try {
                            val content = manifestFile.readText()
                            if (content.contains("package=")) {
                                val newContent = content.replace(Regex("""package="[^"]*""""), "")
                                manifestFile.writeText(newContent)
                            }
                        } catch (e: Exception) {
                            println("Warning: Could not modify manifest for ${project.name}: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {}

            // Fix compileSdkVersion
            try {
                val setCompileSdkVersionMethod = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                setCompileSdkVersionMethod.invoke(android, 35)
            } catch (e: Exception) {}
        }
    }

    if (project.state.executed) {
        configureAndroid()
    } else {
        project.afterEvaluate { configureAndroid() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
