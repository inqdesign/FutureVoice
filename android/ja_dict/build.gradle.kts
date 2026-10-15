import java.net.URI
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/**
 * The Sudachi system dictionary (SudachiDict SMALL, 123 MB raw, ~42 MB as a
 * download) as an ON-DEMAND Play asset pack. Only a Japanese learner fetches
 * it (`JapaneseDictionary.ensure`); everyone else never downloads a byte.
 *
 * On-demand packs are installed as real files, so the app memory-maps the
 * dictionary where Play put it — no copy, no extraction.
 *
 * The dictionary is NOT in git. `fetchSudachiDict` downloads the pinned zip
 * once per machine (checksum-verified, cached in the Gradle user home) and
 * unpacks it into `src/main/assets/sudachi/` (gitignored) — the one place the
 * asset-pack plugin reads from. Every task that packages the bundle, and the
 * unit test that runs real Sudachi, depends on it.
 */
plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName.set("ja_dict")
    dynamicDelivery {
        deliveryType.set("on-demand")
    }
}

abstract class FetchSudachiDict : DefaultTask() {
    @get:Input abstract val url: Property<String>
    @get:Input abstract val sha256: Property<String>
    @get:Internal abstract val cacheFile: RegularFileProperty
    @get:OutputDirectory abstract val outDir: DirectoryProperty

    @TaskAction fun fetch() {
        val zip = cacheFile.get().asFile
        if (!zip.exists() || digest(zip) != sha256.get()) {
            zip.parentFile.mkdirs()
            val part = File(zip.path + ".part")
            URI(url.get()).toURL().openStream().use { input -> part.outputStream().use { input.copyTo(it) } }
            val got = digest(part)
            check(got == sha256.get()) { "SudachiDict checksum mismatch: $got" }
            part.renameTo(zip)
        }
        val out = outDir.get().asFile
        out.mkdirs()
        // Only the dictionary and its licence files; the zip's own folder
        // name is dropped so the app reads a fixed path.
        ZipInputStream(zip.inputStream().buffered()).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                if (e.isDirectory) continue
                val name = e.name.substringAfterLast('/')
                if (name !in setOf("system_small.dic", "LEGAL", "LICENSE-2.0.txt")) continue
                File(out, name).outputStream().use { z.copyTo(it) }
            }
        }
    }

    private fun digest(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) { val n = input.read(buf); if (n < 0) break; md.update(buf, 0, n) }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}

val sudachiDictVersion = "20260723"

tasks.register<FetchSudachiDict>("fetchSudachiDict") {
    url.set("https://d2ej7fkh96fzlu.cloudfront.net/sudachidict/sudachi-dictionary-$sudachiDictVersion-small.zip")
    sha256.set("4729d134fd0b9852dacc89c59229664fee40642bb52bafcf4efb432cee9bb22c")
    cacheFile.set(File(gradle.gradleUserHomeDir,
        "caches/futurevoice/sudachi-dictionary-$sudachiDictVersion-small.zip"))
    outDir.set(layout.projectDirectory.dir("src/main/assets/sudachi"))
}
