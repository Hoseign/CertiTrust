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

// Safely force all subprojects to compile against SDK 36 without evaluation errors
subprojects {
    val configureSdk = Action<Project> {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val method = androidExt.javaClass.getMethod("setCompileSdk", Int::class.java)
                method.invoke(androidExt, 36)
            } catch (e: Exception) {
                try {
                    val method = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                    method.invoke(androidExt, 36)
                } catch (ignored: Exception) {}
            }
        }
    }

    if (state.executed) {
        configureSdk.execute(this)
    } else {
        afterEvaluate(configureSdk)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}