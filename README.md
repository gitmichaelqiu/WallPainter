<h1 align="center">
  <img src="./WallPainter/Resources/WallPainterIcon_Default.png" width="25%" alt=""/>  
  <p></p>
  <p align="center">WallPainter</p>
</h1>
<h3>
<p align="center"><i>Automate wallpaper switches</i></p>
</h3>

**WallPainter** is a macOS menubar app that changes macOS Aerial wallpapers based on your customized rules.

## 📦 Installation

### Direct Download

You do **NOT** have to disable *SIP* or things like that. Your macOS must be at least **macOS 15.0 Ventura**. All you need to do is:

1. Download the package from [Releases](https://github.com/gitmichaelqiu/WallPainter/releases/)
2. Drag the app to the *Applications* folder
3. All set!


### Open App

Because I do **NOT** have an Apple developer account for the app releases, you may receive alerts such as "Developer is not verified".

To resolve this, go to System Settings → the bottom of Privacy & Security → Open WallPainter.

## 🛜 SpaceAPI

To get the current space's information, an extra app DesktopRenamer is required. You can download it [here](https://github.com/gitmichaelqiu/DesktopRenamer/releases/).

After downloading DesktopRenamer, turn on SpaceAPI in DesktopRenamer's Settings → General. WallPainter's Settings → Permissions tab shows the connection status and provides actions to open, launch, or install DesktopRenamer.

## Wallpaper protection

macOS may remove downloaded Aerial assets that have not been used recently. WallPainter automatically keeps a private backup of wallpapers referenced by the Default rule, space overrides, or the current manual selection, then restores them to the Aerial cache before applying a rule.

This is best-effort because Apple does not provide a supported API for pinning live Aerial assets. If a wallpaper cannot be restored, open General → Wallpaper protection and choose Repair, or redownload the wallpaper in System Settings. Unreferenced Aerial wallpapers are never copied by WallPainter.

## ⚠️ Issues

You are welcome to create issues/suggestions in [GitHub Issues](https://github.com/gitmichaelqiu/WallPainter/issues).

If you are curious what I am doing on the project, go to the Issues page. The pinned issues are what I am focusing.

## 🙏 Acknowlegements

This app uses the following packages:

- [Sparkle by @sparkle-project](https://github.com/sparkle-project/Sparkle)

Many thanks to all of these wonderful developers!

See [Acknowledgements.pdf](https://github.com/gitmichaelqiu/WallPainter/blob/main/WallPainter/Resources/Acknowledgements/Acknowledgements.pdf) for licenses.

## ⭐ Support This Project

You can simply click on the **Star** to support this project for free. Thank you for your support!

<a href="https://www.star-history.com/?type=date&legend=top-left&repos=gitmichaelqiu%2FWallPainter">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=gitmichaelqiu/WallPainter&type=date&theme=dark&legend=top-left&sealed_token=SlB6XMb-xB5ZOuVg9ffHN1FHBtXnXz1t6JNcX-1URygva-p2fIbnMbgA-HxOkgEk9xgjwidgyfFYFHyOv1G3KJ6Gswr_zuFvlomB2RMgNWLgKJiGxVw4mw" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=gitmichaelqiu/WallPainter&type=date&legend=top-left&sealed_token=SlB6XMb-xB5ZOuVg9ffHN1FHBtXnXz1t6JNcX-1URygva-p2fIbnMbgA-HxOkgEk9xgjwidgyfFYFHyOv1G3KJ6Gswr_zuFvlomB2RMgNWLgKJiGxVw4mw" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=gitmichaelqiu/WallPainter&type=date&legend=top-left&sealed_token=SlB6XMb-xB5ZOuVg9ffHN1FHBtXnXz1t6JNcX-1URygva-p2fIbnMbgA-HxOkgEk9xgjwidgyfFYFHyOv1G3KJ6Gswr_zuFvlomB2RMgNWLgKJiGxVw4mw" />
 </picture>
</a>
