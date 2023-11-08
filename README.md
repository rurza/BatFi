# BatFi
BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100% only when it's needed.

<a href="https://micropixels.gumroad.com/l/batfi">
    <img width="200" alt="buy_on_gumroad" src="https://github-production-user-asset-6210df.s3.amazonaws.com/2467137/269984099-a4628c9d-10a8-4c83-a3cc-dfe04fef71d8.png">
</a>
<p><sub><sup>Requires macOS Ventura or later and Apple Silicon Mac</sup></sub></p>
<br>

## Why?
Maintaining a lithium-ion battery at a high state of charge can significantly reduce its lifespan. Although macOS offers a feature that automatically postpones charging the battery to 100%, it lacks user control. This automated approach relies on machine learning to adapt to user habits, leaving users without the ability to determine when and how long the charging should be delayed. Consequently, this solution may not be effective for users with irregular computer usage patterns or for devices frequently connected to power sources, such as monitors like Apple's Studio Display or Pro Display XDR.

On the other hand, BatFi works differently. The app allows you to set a user-chosen limit for charging the battery and maintain it indefinitely. With BatFi, you have the flexibility to decide when to charge the battery to 100% based on your usage needs.

<p float="left">
  <img src="https://github.com/rurza/BatFi/assets/2467137/db8870bb-0a61-4088-a361-b44d0db2cff7" width=300>
  <img src="https://github.com/rurza/BatFi/assets/2467137/8cf4f6e3-fbe9-48ee-b034-b6fa8f0dc50c" width=300>
  <img src="https://github.com/rurza/BatFi/assets/2467137/ad75de07-157b-48ba-8584-27ce930d078e" width=300>
</p>

## Localization

The app uses [String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) which makes localization super straightforward.

<details>
<summary>If you know how to use Git</summary>
    
1) Install Xcode 15 ([Mac App Store](https://apps.apple.com/us/app/xcode/id497799835?mt=12))
2) Fork this repo, the develop branch
3) Open and edit `./BatFiKit/Sources/L10n/Localizable.xcstrings` with Xcode 15
4) Commit changes and make pull request

</details>

<details>
<summary>If you have no idea what Git is</summary>
    
1) Install Xcode 15 ([Mac App Store](https://apps.apple.com/us/app/xcode/id497799835?mt=12))
2) Download [Localizable.xcstrings](https://github.com/rurza/BatFi/blob/develop/BatFiKit/Sources/L10n/Localizable.xcstrings) using the "Download raw file" button in the top right corner
3) Open and edit downloaded file. It'll open in Xcode
4) Send it to me: adam@micropixels.pl

</details>

