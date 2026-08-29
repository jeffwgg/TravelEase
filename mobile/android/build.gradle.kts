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

// Old plugins (e.g. video_player_android 2.4.x) compile with -Werror, which
// fails on JDK 17+ because "source value 8 is obsolete" is emitted as a
// warning. Strip it so legacy dependency sources still compile.
subprojects {
    if (state.executed) {
        tasks.withType(JavaCompile::class.java).configureEach {
            options.compilerArgs.removeAll { it == "-Werror" }
        }
    } else {
        afterEvaluate {
            tasks.withType(JavaCompile::class.java).configureEach {
                options.compilerArgs.removeAll { it == "-Werror" }
            }
        }
    }
}

// Keep dependency Kotlin bytecode within the app's JVM 17 target. Some older
// Flutter plugins still compile their Java sources for JVM 8 or 11.
subprojects {
    if (state.executed) {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    } else {
        afterEvaluate {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
