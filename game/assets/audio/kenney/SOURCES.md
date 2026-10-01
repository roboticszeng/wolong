# Kenney：音效素材来源

来源：[Interface Sounds](https://kenney.nl/assets/interface-sounds)，版本1.0，共100个音效。本项目选用其中10个原始Ogg文件，下载日期2026-10-01。

原包：https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip

原作者随包License.txt已保留。授权为CC0，可用于商业游戏；本项目仍在行囊和声音设置中鸣谢Kenney。

原始10个音效保留为素材备选。现行版本额外从同包选用click_002.ogg，生成click_crisp.wav：解码为单声道16位PCM，去掉起始静音、消除直流偏移，控制幅度，并做极短淡入与尾部淡出。最终长度约9.9毫秒。可用game/tools/prepare_click.gd重新生成，衍生文件沿用CC0授权。

所有操作与事件统一使用这个短促点击，不再播放原先的开关、翻页、拨弦和钟声素材。这些是游戏提示音，不是古代场景实地录音。
