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
// Raise any plugin module that asks for a Kotlin language version this
// toolchain no longer accepts.
//
// `settings.gradle.kts` pins Kotlin 2.2.20, which dropped language versions
// below 1.8. `sentry_flutter` 8.14.2 hardcodes `languageVersion = "1.6"` in its
// own build.gradle and so fails to compile — and its 9.x line, which removed
// that line, is unusable here for a different reason (see the note beside the
// dependency in pubspec.yaml). Bumping it to 1.8 is safe: nothing is being
// asked to *use* newer language features, only to stop requesting a retired
// flag.
//
// Applies to `subprojects` only, so `:app` keeps the toolchain default, and it
// raises rather than pins — a plugin that legitimately wants 2.x is untouched.
// `configureEach` is lazy, so it lands after each plugin's own `kotlinOptions`
// block; it must also stay ABOVE the `evaluationDependsOn` below, which forces
// evaluation and would leave nothing left to configure.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            val minimum = org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8
            if ((languageVersion.orNull ?: minimum) < minimum) {
                languageVersion.set(minimum)
                apiVersion.set(minimum)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
