package com.retroplay.app.compatibility.device

import com.retroplay.app.core.coroutines.IoDispatcher
import com.retroplay.app.domain.device.DeviceProfileComparator
import com.retroplay.app.domain.model.ComparisonRow
import com.retroplay.app.domain.model.DeviceProfile
import com.retroplay.app.domain.model.GpuInfo
import com.retroplay.app.domain.model.ReferenceDeviceProfile
import com.retroplay.app.domain.model.ReferenceProfiles
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.cancellation.CancellationException

/** Produces runtime hardware profiles and compares them with the target reference device. */
interface DeviceProfileManager {
    val referenceProfile: ReferenceDeviceProfile
    suspend fun captureProfile(): DeviceProfile
    fun compareWithReference(profile: DeviceProfile): List<ComparisonRow>
}

@Singleton
class DefaultDeviceProfileManager @Inject constructor(
    private val source: DeviceInfoSource,
    private val gpuInfoProvider: GpuInfoProvider,
    @IoDispatcher private val ioDispatcher: CoroutineDispatcher,
) : DeviceProfileManager {

    override val referenceProfile: ReferenceDeviceProfile = ReferenceProfiles.Pixel9

    private val gpuLock = Mutex()
    private var cachedGpuInfo: GpuInfo? = null

    override suspend fun captureProfile(): DeviceProfile = withContext(ioDispatcher) {
        DeviceProfile(
            capturedAtEpochMillis = System.currentTimeMillis(),
            identity = source.identity(),
            os = source.os(),
            cpu = source.cpu(),
            memory = source.memory(),
            gpu = gpuInfo(),
            graphicsApis = source.graphicsApis(),
            display = source.display(),
            storage = source.storage(),
            thermalStatus = source.thermalStatus(),
        )
    }

    override fun compareWithReference(profile: DeviceProfile): List<ComparisonRow> =
        DeviceProfileComparator.compare(profile, referenceProfile)

    /** GPU driver strings do not change while the app runs, so a successful query is cached. */
    private suspend fun gpuInfo(): GpuInfo = gpuLock.withLock {
        cachedGpuInfo ?: try {
            gpuInfoProvider.queryGpuInfo()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            GpuInfo.unavailable(e.message ?: e::class.java.simpleName)
        }.also { if (it.isAvailable) cachedGpuInfo = it }
    }
}
