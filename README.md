<div dir="rtl">

# khaled_cli HQ

يجهّز مقاطعك للرفع على تيك توك، عشان تنعرض بجودتها الأصلية (لين 4K و 120 فريم) بدل ما تنضغط.

تطبيق صغير للماك، وخيار في الكلك يمين. تسحب المقطع، وبعد دقيقة تقريباً يطلع لك ملف جاهز للرفع.

## التركيب

افتح تطبيق «Terminal» والصق هالأمر:

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/install.sh | bash
```

<div dir="rtl">

ياخذ تقريباً دقيقتين، وما يحتاج كلمة سر.

**المتطلبات:**
- ماك بمعالج Apple (‏M1 أو أحدث). أجهزة Intel مو مدعومة.
- نظام macOS 15 أو أجدد.
- أدوات أبل للمطورين (Command Line Tools). إذا ناقصة، الأمر يفتح لك نافذة أبل تركّبها، وبعدها تعيد نفس الأمر.

## الاستخدام

- **التطبيق:** افتح «khaled_cli HQ» من مجلد التطبيقات، واسحب عليه المقطع (أو على أيقونته في الـ Dock). تقدر تختار 4K أو 1080p.
- **الكلك يمين:** في Finder، كلك يمين على المقطع › Quick Actions › ‏`khaled_cli HQ · 4K` أو `khaled_cli HQ · 1080p`.

الناتج ينحفظ جنب المقطع الأصلي باسم `<الاسم>_4K_khaled_cli.mp4`. الأصلي ما ينلمس.

**ارفعه من متصفح الكمبيوتر:** ‏[tiktok.com/tiktokstudio/upload](https://www.tiktok.com/tiktokstudio/upload)، مو من تطبيق الجوال.

## أول مرة

- الماك بيسألك إذا تسمح للأداة توصل لمجلد المقطع (سطح المكتب أو التنزيلات أو المستندات). اضغط **السماح**، وإلا ما تقدر تقرا المقطع.
- التطبيق بيسألك عن الإشعارات، عشان يعلمك لما يخلص.
- إذا ما طلع الخيار في الكلك يمين: كلك يمين › Quick Actions › ‏Customize…، وفعّل `khaled_cli HQ`.

## التحديث والحذف

التحديث: نفس أمر التركيب.

الحذف (مقاطعك ونواتجها ما تنلمس):

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/uninstall.sh | bash
```

<div dir="rtl">

## ملاحظات

- كل الشغل يصير في جهازك. الأداة ما ترسل أي شي لأي مكان.
- قبل ما تقول «جاهز»، الأداة تفحص الناتج: عدد الفريمات، والمدة، والصوت، وإن الصورة مطابقة للمصدر. إذا لقت مشكلة، يطلع الملف باسم فيه `CHECK-FAILED`، فلا ترفعه.
- تيك توك ممكن يغيّر طريقة تعامله مع المقاطع بأي وقت، فما في ضمان إنها تشتغل دايماً. الاستخدام على مسؤوليتك.
- أمر التركيب ينزّل FFmpeg 9.0.2 من [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de/)، ويتأكد من بصمته وتوقيعه قبل ما يركّبه.

</div>

---

## English

Prepares your videos for TikTok so they play at their original quality (up to 4K, 120 fps) instead of being re-compressed. A small Mac app plus a Finder right-click action.

**Install** (Apple Silicon Mac, macOS 15 or later, Apple Command Line Tools):

```bash
curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/install.sh | bash
```

**Use:** drop a video on the **khaled_cli HQ** app, or right-click it in Finder › Quick Actions › `khaled_cli HQ · 4K`. The result is saved next to the original as `<name>_4K_khaled_cli.mp4`. Upload it from a desktop browser at [tiktok.com/tiktokstudio/upload](https://www.tiktok.com/tiktokstudio/upload), not from the phone app.

**Update:** run the install command again. **Uninstall:**

```bash
curl -fsSL https://raw.githubusercontent.com/Khxxxxd/khaled-cli-hq/main/uninstall.sh | bash
```

Everything runs locally; nothing is sent anywhere. Every output is checked (frame count, duration, audio, picture match) before it is marked ready. TikTok can change how it handles uploads at any time, so there is no guarantee. Use at your own risk. The installer downloads FFmpeg 9.0.2 from [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de/) and verifies its checksum and signature.

---

Made by [@khaled_cli](https://x.com/khaled_cli) · [MIT](LICENSE) · Uses tiktok-quality (MIT)
