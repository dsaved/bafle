# Integration Guide

This guide explains how to integrate the bootstrap system into your mobile code editor app.

## Quick Start

### 1. Fetch Bootstrap Manifest

Use the stable "latest" URL to always get the most recent bootstrap version:

```kotlin
val manifestUrl = "https://github.com/dsaved/bafle/releases/latest/download/bootstrap-manifest.json"
```

### 2. Parse Manifest

```kotlin
data class BootstrapManifest(
    val version: String,
    val last_updated: String,
    val architectures: Map<String, ArchitectureInfo>
)

data class ArchitectureInfo(
    val url: String,
    val size: Long,
    val checksum: String,
    val min_android_version: Int
)

val manifest = Json.decodeFromString<BootstrapManifest>(manifestJson)
```

### 3. Detect Device Architecture

```kotlin
fun getDeviceArchitecture(): String {
    return when (Build.SUPPORTED_ABIS[0]) {
        "arm64-v8a" -> "arm64-v8a"
        "armeabi-v7a" -> "armeabi-v7a"
        "x86_64" -> "x86_64"
        "x86" -> "x86"
        else -> "arm64-v8a" // fallback
    }
}
```

### 4. Download Bootstrap

```kotlin
val arch = getDeviceArchitecture()
val bootstrapInfo = manifest.architectures[arch]
    ?: throw Exception("Architecture $arch not supported")

// Check if update is needed
val currentVersion = getInstalledBootstrapVersion()
if (currentVersion != manifest.version) {
    downloadBootstrap(bootstrapInfo)
}
```

### 5. Verify Checksum

```kotlin
fun verifyChecksum(file: File, expectedChecksum: String): Boolean {
    val digest = MessageDigest.getInstance("SHA-256")
    val hash = file.inputStream().use { input ->
        val buffer = ByteArray(8192)
        var bytesRead: Int
        while (input.read(buffer).also { bytesRead = it } != -1) {
            digest.update(buffer, 0, bytesRead)
        }
        digest.digest()
    }
    
    val actualChecksum = "sha256:" + hash.joinToString("") { 
        "%02x".format(it) 
    }
    
    return actualChecksum == expectedChecksum
}
```

### 6. Extract Bootstrap

```kotlin
fun extractBootstrap(tarGzFile: File, targetDir: File) {
    // Extract tar.gz archive
    TarArchiveInputStream(
        GzipCompressorInputStream(
            BufferedInputStream(FileInputStream(tarGzFile))
        )
    ).use { tarInput ->
        var entry: TarArchiveEntry?
        while (tarInput.nextTarEntry.also { entry = it } != null) {
            val outputFile = File(targetDir, entry!!.name)
            
            if (entry!!.isDirectory) {
                outputFile.mkdirs()
            } else {
                outputFile.parentFile?.mkdirs()
                outputFile.outputStream().use { output ->
                    tarInput.copyTo(output)
                }
                
                // Set executable permissions if needed
                if (entry!!.mode and 0x49 != 0) { // Check execute bits
                    outputFile.setExecutable(true)
                }
            }
        }
    }
}
```

## Complete Example

```kotlin
class BootstrapManager(private val context: Context) {
    private val manifestUrl = "https://github.com/dsaved/bafle/releases/latest/download/bootstrap-manifest.json"
    private val bootstrapDir = File(context.filesDir, "bootstrap")
    private val versionFile = File(bootstrapDir, ".version")
    
    suspend fun updateBootstrap(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            // 1. Fetch manifest
            val manifest = fetchManifest()
            
            // 2. Check if update needed
            val currentVersion = getInstalledVersion()
            if (currentVersion == manifest.version) {
                return@withContext Result.success(Unit)
            }
            
            // 3. Get architecture info
            val arch = getDeviceArchitecture()
            val bootstrapInfo = manifest.architectures[arch]
                ?: return@withContext Result.failure(
                    Exception("Architecture $arch not supported")
                )
            
            // 4. Download bootstrap
            val downloadFile = File(context.cacheDir, "bootstrap.tar.gz")
            downloadBootstrap(bootstrapInfo.url, downloadFile)
            
            // 5. Verify checksum
            if (!verifyChecksum(downloadFile, bootstrapInfo.checksum)) {
                return@withContext Result.failure(
                    Exception("Checksum verification failed")
                )
            }
            
            // 6. Extract bootstrap
            val tempDir = File(context.cacheDir, "bootstrap-temp")
            tempDir.deleteRecursively()
            tempDir.mkdirs()
            
            extractBootstrap(downloadFile, tempDir)
            
            // 7. Replace old bootstrap
            bootstrapDir.deleteRecursively()
            tempDir.renameTo(bootstrapDir)
            
            // 8. Save version
            versionFile.writeText(manifest.version)
            
            // 9. Cleanup
            downloadFile.delete()
            
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    private suspend fun fetchManifest(): BootstrapManifest {
        val response = httpClient.get(manifestUrl)
        return Json.decodeFromString(response.bodyAsText())
    }
    
    private fun getInstalledVersion(): String? {
        return if (versionFile.exists()) {
            versionFile.readText().trim()
        } else {
            null
        }
    }
    
    private fun getDeviceArchitecture(): String {
        return when (Build.SUPPORTED_ABIS[0]) {
            "arm64-v8a" -> "arm64-v8a"
            "armeabi-v7a" -> "armeabi-v7a"
            "x86_64" -> "x86_64"
            "x86" -> "x86"
            else -> "arm64-v8a"
        }
    }
    
    private suspend fun downloadBootstrap(url: String, outputFile: File) {
        httpClient.get(url).bodyAsChannel().copyTo(outputFile)
    }
    
    private fun verifyChecksum(file: File, expectedChecksum: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
            digest.digest()
        }
        
        val actualChecksum = "sha256:" + hash.joinToString("") { 
            "%02x".format(it) 
        }
        
        return actualChecksum == expectedChecksum
    }
    
    private fun extractBootstrap(tarGzFile: File, targetDir: File) {
        TarArchiveInputStream(
            GzipCompressorInputStream(
                BufferedInputStream(FileInputStream(tarGzFile))
            )
        ).use { tarInput ->
            var entry: TarArchiveEntry?
            while (tarInput.nextTarEntry.also { entry = it } != null) {
                val outputFile = File(targetDir, entry!!.name)
                
                if (entry!!.isDirectory) {
                    outputFile.mkdirs()
                } else {
                    outputFile.parentFile?.mkdirs()
                    outputFile.outputStream().use { output ->
                        tarInput.copyTo(output)
                    }
                    
                    if (entry!!.mode and 0x49 != 0) {
                        outputFile.setExecutable(true)
                    }
                }
            }
        }
    }
}
```

## Usage in App

```kotlin
// In your Application class or initialization code
class MyApp : Application() {
    private lateinit var bootstrapManager: BootstrapManager
    
    override fun onCreate() {
        super.onCreate()
        
        bootstrapManager = BootstrapManager(this)
        
        // Check for updates on app start
        lifecycleScope.launch {
            bootstrapManager.updateBootstrap()
                .onSuccess {
                    Log.i("Bootstrap", "Bootstrap updated successfully")
                }
                .onFailure { error ->
                    Log.e("Bootstrap", "Bootstrap update failed", error)
                }
        }
    }
}
```

## Update Strategy

### On App Start
Check for bootstrap updates when the app starts. This ensures users get the latest tools without manual intervention.

### Background Updates
Consider checking for updates periodically in the background:

```kotlin
WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    "bootstrap-update",
    ExistingPeriodicWorkPolicy.KEEP,
    PeriodicWorkRequestBuilder<BootstrapUpdateWorker>(1, TimeUnit.DAYS)
        .setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()
        )
        .build()
)
```

### Manual Updates
Provide a manual update option in settings:

```kotlin
// In settings screen
Button(onClick = {
    scope.launch {
        showLoading()
        bootstrapManager.updateBootstrap()
            .onSuccess { showSuccess() }
            .onFailure { showError(it) }
    }
}) {
    Text("Update Bootstrap")
}
```

## Dependencies

Add these dependencies to your `build.gradle`:

```gradle
dependencies {
    // For HTTP requests
    implementation("io.ktor:ktor-client-android:2.3.0")
    
    // For JSON parsing
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.5.1")
    
    // For tar.gz extraction
    implementation("org.apache.commons:commons-compress:1.24.0")
    
    // For background updates
    implementation("androidx.work:work-runtime-ktx:2.8.1")
}
```

## Bootstrap Structure

After extraction, the bootstrap will have this structure:

```
bootstrap/
└── usr/
    ├── bin/          # Executables (bash, apt, dpkg, etc.)
    ├── lib/          # Shared libraries
    ├── etc/          # Configuration files
    ├── share/        # Shared data
    ├── var/          # Variable data
    ├── tmp/          # Temporary files
    └── libexec/      # Helper executables
```

## Environment Setup

Set up the environment for running commands:

```kotlin
fun setupEnvironment(): Map<String, String> {
    val bootstrapPath = File(context.filesDir, "bootstrap/usr")
    
    return mapOf(
        "HOME" to context.filesDir.absolutePath,
        "PREFIX" to bootstrapPath.absolutePath,
        "PATH" to "${bootstrapPath}/bin:${System.getenv("PATH")}",
        "LD_LIBRARY_PATH" to "${bootstrapPath}/lib",
        "TMPDIR" to context.cacheDir.absolutePath
    )
}
```

## Running Commands

```kotlin
fun runCommand(command: String): Process {
    val env = setupEnvironment()
    val processBuilder = ProcessBuilder("/bin/sh", "-c", command)
    
    processBuilder.environment().clear()
    processBuilder.environment().putAll(env)
    
    return processBuilder.start()
}
```

## Troubleshooting

### Checksum Verification Fails
- Ensure the download completed successfully
- Check network connectivity
- Retry the download

### Extraction Fails
- Verify sufficient storage space
- Check file permissions
- Ensure the downloaded file is not corrupted

### Commands Don't Work
- Verify bootstrap is extracted correctly
- Check environment variables are set
- Ensure executable permissions are set on binaries

## Best Practices

1. **Always verify checksums** before extracting
2. **Use atomic updates** - extract to temp directory, then rename
3. **Handle errors gracefully** - don't leave app in broken state
4. **Show progress** to users during download/extraction
5. **Test on all architectures** before releasing
6. **Keep old version** until new one is verified
7. **Log errors** for debugging

## Security Considerations

1. **HTTPS Only**: Always use HTTPS URLs
2. **Verify Checksums**: Never skip checksum verification
3. **Validate Manifest**: Ensure manifest JSON is well-formed
4. **Sandboxing**: Run commands in isolated environment
5. **Permissions**: Request only necessary permissions
6. **Updates**: Keep bootstrap updated for security patches
