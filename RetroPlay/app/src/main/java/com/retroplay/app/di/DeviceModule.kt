package com.retroplay.app.di

import com.retroplay.app.compatibility.device.DefaultDeviceProfileManager
import com.retroplay.app.compatibility.device.DeviceInfoSource
import com.retroplay.app.compatibility.device.DeviceProfileManager
import com.retroplay.app.compatibility.device.GpuInfoProvider
import com.retroplay.app.data.device.AndroidDeviceInfoSource
import com.retroplay.app.data.device.EglGpuInfoProvider
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class DeviceModule {
    @Binds abstract fun bindDeviceInfoSource(impl: AndroidDeviceInfoSource): DeviceInfoSource
    @Binds abstract fun bindGpuInfoProvider(impl: EglGpuInfoProvider): GpuInfoProvider
    @Binds abstract fun bindDeviceProfileManager(impl: DefaultDeviceProfileManager): DeviceProfileManager
}
