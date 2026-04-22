# Mesai (Clock In / Clock Out)

Personelin günlük mesai başlangıç ve bitişini audit log üzerinden takip eden feature. Ayrı bir "shift" tablosu **yoktur** — kaynak doğrudan `audit_log` satırlarıdır.

**Dizin**: `apps/pos/lib/features/shifts/`

## Neden ayrı tablo yok

Mesai başlama / bitiş zaten audit olayı. Ayrı bir tablo tutmak:

- İkinci bir migration (v17) gerektirir.
- Audit log ile sync problemi yaratır (hangisi doğru?).
- History window sorgusu ekstra join ister.

Bunun yerine: **audit log `source of truth`**, üstüne saf bir reducer yazıyoruz. Reducer satırları dakika içinde eriterek her kullanıcı için `ClockStatus` üretir.

## Dosyalar

```
features/shifts/
├── domain/
│   └── entities/
│       └── clock_status.dart          # userId, isClockedIn, workedToday
├── data/
│   └── clock_repository.dart          # getStatuses() + reduceStatuses() (saf)
└── presentation/
    └── providers/
        └── clock_provider.dart        # AsyncNotifier + tile view model
```

UI tarafı: `apps/pos/lib/features/backoffice/presentation/widgets/clock_management_tab.dart`.

## Audit aksiyonları

`features/audit_log/domain/entities/audit_action.dart`:

```dart
userClockedIn('User Clocked In'),
userClockedOut('User Clocked Out'),
```

Bu aksiyonlar `AuditLogScreen` içinde `(AppColors.purple, Icons.schedule_rounded)` ile render edilir.

Yazma tarafı: `AuditService.logUserClockedIn(userId, name)` ve `logUserClockedOut(userId, name, {reason})`.

## Reducer state machine

`ClockRepository.reduceStatuses({rows, now})` — saf, statik fonksiyon. Audit satırlarını en eskiden en yeniye yürütür, kullanıcı başına bir `_Acc` akümülatörü tutar:

| Olay | Acc'ye etkisi |
|------|--------------|
| `userClockedIn` (open yok) | `openSince = at` |
| `userClockedIn` (open var) | **Eski open override**. Çift clockIn = unutulmuş bir çıkış; stale aralık sayılmaz. |
| `userClockedOut` (open var) | Kapalı aralık eklenir, `openSince = null`, `lastClockOut = at` |
| `userClockedOut` (open yok) | Sadece `lastClockOut` güncellenir — orphan clockOut aralık üretmez |
| Diğer aksiyonlar | Görmezden gelinir |

`workedToday` hesaplanırken her kapalı aralık `[dayStart, dayEnd)` penceresine **clamp** edilir. Gece yarısını geçen bir mesai sadece "bugüne düşen" parçayı katar.

## Live timer

`ClockTileViewModel.totalWorked`: kullanıcı hâlâ clockedIn ise `workedToday + (now - openSince)` ekler. UI 30 saniyede bir `Timer.periodic` ile `setState` çağırarak "Bugün: H:MM" label'ını günceller.

## Back Office Mesai sekmesi

`ClockManagementTab`:

- Tüm aktif kullanıcıları listeler (`usersListProvider` + `isActive` filter).
- Listeye ekstra olarak: kullanıcı deaktive edilmiş ama hâlâ clockedIn ise gene gösterilir (manager clockOut edebilsin diye).
- Row başına avatar, MESAIDE/OFF rozeti, "Bugun: Hh MMm" etiketi, "Mesai Baslat" / "Mesai Bitir" butonu.
- Tek tuşla toggle: `ClockStatusesNotifier.toggle({userId, userName, currentlyClockedIn})` audit servisi üzerinden yazar, sonra `_refresh()`.

## Testler

`apps/pos/test/features/shifts/clock_repository_test.dart` — reducer için 10 test:

- Boş rows → boş list.
- Tek clockIn → `isClockedIn=true`, `workedToday=0`.
- clockIn + clockOut → kapalı aralık toplanır.
- İki aralık toplanır.
- Çift clockIn → ikincisi stamp'i ezer.
- Orphan clockOut → aralık yok, sadece lastClockOut.
- Dün 22:00 → bugün 02:00 = 2 saat (overnight clamp).
- Alakasız aksiyonlar göz ardı.
- Çok-kullanıcılı bağımsız takip.
- En son audit satırındaki kullanıcı adı kazanır.

Saf fonksiyon olduğu için Flutter çevresine gerek yok — `dart:async` yeterli.

## Hatırlatma

- `historyWindow` default 7 gün; "Bu hafta toplam" gibi bir raporlama eklendiğinde burayı 30 gün'e çıkarın.
- DAO query 500 satırla cap'li. Yoğun restoranda (günde 100+ olay) 3 günden fazla geriye gitmek için cap'i artırın veya paging ekleyin.
