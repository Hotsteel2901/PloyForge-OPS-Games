BGM 恢复为 OGG 预渲染播放（替代实时 MIDI 合成，消除 Web 卡顿）：
- BGM 使用 4 首 OGG 离线渲染音乐（ObsidianCircuit / ChromeDistrict / NeonVault / ShatterCore）
- Web 端 OGG 采用 sample 化完整解码播放（已验证播放链正常）
- 保留音效预合成、关闭音乐不影响音效、音量基准等修复
