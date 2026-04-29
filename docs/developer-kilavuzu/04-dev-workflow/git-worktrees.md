# Git Worktrees

Bu repo geliştirme sırasında yoğun şekilde git worktree'leri kullanır. Nedir, nasıl kullanılır, nelere dikkat edilir.

## Ne Yapar

Git worktree = aynı repo'yu farklı bir dizinde, farklı bir branch'te checkout etmek. Branch switch sırasında kod kaybetmeden paralel çalışmayı mümkün kılar.

**Main repo**: `E:\Project\Restaurant\` - tipik olarak `main` branch.

**Worktrees**: `E:\Project\Restaurant\.claude\worktrees\<name>\` - her biri farklı branch'te aktif çalışma dizini.

## Repo'daki Worktree'ler

```
.claude/worktrees/
├── jolly-final/          # Pilot-final çalışma worktree (claude/pilot-final)
├── hodgkin/              # Daha önce aktif (merge alindi)
├── shannon/              # Printer config worktree (merge alindi)
├── quizzical-fermat/     # i18n pilot (merge alindi)
└── sweet-feistel-4e5dfc/ # Abandoned (SADECE referans için)
```

Aktif pilot geliştirmesi `jolly-final` içinde yapılıyor. Main repoda (`E:\Project\Restaurant\`) branch `main` sabit.

## Yeni Worktree Yaratmak

```bash
# Mevcut branch üzerinden
git worktree add .claude/worktrees/yeni-is claude/yeni-is

# Yeni branch ile birlikte
git worktree add -b claude/yeni-feature .claude/worktrees/yeni-feature main
```

Sonra o dizine gir ve orada çalış:
```bash
cd .claude/worktrees/yeni-feature
```

## Worktree Listesini Görmek

```bash
git worktree list
```

Çıktı:
```
E:/Project/Restaurant                     a20acc3 [main]
E:/Project/Restaurant/.claude/worktrees/jolly-final   a20acc3 [claude/pilot-final]
...
```

## Worktree Silmek

```bash
git worktree remove .claude/worktrees/abandoned-wt
```

Eğer worktree dizini silindiyse ama git referansı kaldıysa:
```bash
git worktree prune
```

## Hangi Worktree'de Olduğunu Anlamak

```bash
pwd                          # şu an hangi dizindeyim
git branch --show-current    # şu anki branch
git worktree list            # tüm worktree'ler ve branch'leri
```

**Klasik hata**: Main repo'da `E:\Project\Restaurant\` düşünürken aslında bir worktree'desin. Branch adı + dizin her zaman teyit et.

## Aktif Worktree Seçmek (Genel Kural)

1. `jolly-final` varsa pilot-final iş o. Kullan.
2. Yoksa, `hodgkin` fallback. Son merge'den önce aktifti.
3. `sweet-feistel` = DO NOT USE. Abandoned. Erişirsen kafaların karışır.

Bu kılavuz `jolly-final` baz alınarak yazıldı. Satır numaraları ve dosya yolları buna göredir.

## Worktree + Build Etkileşimi

Her worktree ayrı `build/` dizini tutar. POS için:
```
.claude/worktrees/jolly-final/apps/pos/build/app/outputs/flutter-apk/app-release.apk
```

Bu APK sadece o worktree'nin branch'indeki commit'ten üretilmiş. Başka worktree'de başka APK vardır.

**Pilot release pattern**:
1. `jolly-final`'da build ver.
2. APK'yi main repo'ya kopyala:
```bash
cp .claude/worktrees/jolly-final/apps/pos/build/app/outputs/flutter-apk/app-release.apk \
   E:/Project/Restaurant/pilot/jolly-final-v1.3.0.apk
```
3. Sha256 hesapla.
4. Commit + tag.

## Nested Worktree Tuzağı

Bir worktree içinde başka git dizinlerinin `.git` pointer'ı karışabilir. Geçmişte bu olmuş, commit mesajlari:
```
chore: strip nested worktree pointers from shannon merge
chore: unstage nested worktree pointers that slipped into hodgkin merge
```

Belirti: `git status` içinde `modified: .claude/worktrees/xxx` görüyorsan, bu pointer sıkıntısı. Çözüm:
```bash
git restore --staged .claude/worktrees/
```

Nested worktree'ler ebeveyn repo'nun izleme alanının dışında olmalı.

## Claude Code'un Worktree Kullanımı

Claude Code isolation modunda otomatik worktree açar (Agent tool `isolation: "worktree"` opsiyonu). Ama bu kılavuz manuel oluşturulmuş worktree'lerdeki iş için.

Session başında Claude'a hangi worktree'nin aktif olduğunu söylemek şart. `E:\Project\Restaurant\.claude\worktrees\jolly-final`.

## Temiz Olması İçin

- Worktree'ler uzun yaşamamalı. 1-2 günlük fetch -> merge -> sil.
- Merge edilen worktree hemen silinmeli (`git worktree remove`).
- Unused branch'lar temizlenmeli: `git branch -d claude/eski-branch`.

Aksi halde `.claude/worktrees/` giderek şişer.

## Merge Akışı

Tipik flow:
1. `main` üzerinde start.
2. `git worktree add` ile yeni worktree, yeni branch.
3. Worktree'de kod yaz.
4. Commit -> push (varsa remote).
5. Ana repo'ya dön: `cd E:/Project/Restaurant`.
6. `git merge claude/pilot-final --no-ff` veya PR merge.
7. Worktree sil: `git worktree remove .claude/worktrees/jolly-final`.
8. Branch sil: `git branch -d claude/pilot-final`.

## IDE (VS Code) Integration

VS Code her worktree'yi ayrı workspace olarak aç. Birden fazla açıksa ayrı pencereler. Karışmaması için window title'a branch eklenir.

`.vscode/` klasörü worktree'ye özgü olmayabilir - genelde root'ta. Her worktree aynı settings.json'u okur.

## Temel Komutlar Özeti

```bash
# Liste
git worktree list

# Yarat
git worktree add -b claude/feat-x .claude/worktrees/feat-x main

# Sil
git worktree remove .claude/worktrees/feat-x

# Prune (dizini silindiyse git refs temizle)
git worktree prune

# Hangi branch (worktree içindeyken)
git branch --show-current

# Hangi dizindeyim
pwd
```
