/// First-run onboarding wizard for GastroCore POS.
///
/// A 4-step setup flow that collects the minimum information needed to
/// configure a restaurant's POS for the first time:
///
///   1. Welcome — branding, language selection
///   2. Restaurant info — name, address, currency
///   3. Table setup — number of floors / tables (quick-setup)
///   4. Complete — ready to go
///
/// On completion, `onboarding_complete = true` is written to
/// [SharedPreferences] and the user is sent to the PIN login screen.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 4;

  // Step 2 - Restaurant info
  final _restaurantNameCtrl = TextEditingController();
  final _restaurantAddressCtrl = TextEditingController();
  String _selectedCurrency = 'CHF';
  String _selectedCountry = 'CH';

  // Step 3 - Table setup
  int _floorCount = 1;
  int _tablesPerFloor = 8;

  // Slide + fade for page content
  late final AnimationController _stepAnimController;
  late final Animation<double> _stepFade;
  late final Animation<Offset> _stepSlide;

  final _currencies = ['CHF', 'EUR', 'USD', 'GBP', 'TRY'];
  final _countries = {'CH': 'İsviçre', 'DE': 'Almanya', 'AT': 'Avusturya', 'TR': 'Türkiye', 'FR': 'Fransa'};

  @override
  void initState() {
    super.initState();
    _stepAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _stepFade = CurvedAnimation(
      parent: _stepAnimController,
      curve: Curves.easeOut,
    );
    _stepSlide = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _stepAnimController,
      curve: Curves.easeOutCubic,
    ));
    _stepAnimController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _restaurantNameCtrl.dispose();
    _restaurantAddressCtrl.dispose();
    _stepAnimController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_currentStep < _totalSteps - 1) {
      await _stepAnimController.reverse();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
      _stepAnimController.forward();
    } else {
      await _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (_restaurantNameCtrl.text.isNotEmpty) {
      await prefs.setString('restaurant_name', _restaurantNameCtrl.text.trim());
    }
    if (_restaurantAddressCtrl.text.isNotEmpty) {
      await prefs.setString('restaurant_address', _restaurantAddressCtrl.text.trim());
    }
    await prefs.setString('currency', _selectedCurrency);
    await prefs.setString('country', _selectedCountry);
    await prefs.setInt('floor_count', _floorCount);
    await prefs.setInt('tables_per_floor', _tablesPerFloor);

    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
      ),
    );
  }

  // ── Wide layout (tablet / landscape) ──────────────────────────────────────

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left panel — branding sidebar
        Container(
          width: 280,
          color: AppColors.surface,
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GastroLogo(),
              const SizedBox(height: 48),
              ..._buildStepIndicators(vertical: true),
            ],
          ),
        ),
        // Right panel — form content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildPageContent()),
                _buildNavButtons(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Narrow layout (phone / portrait) ──────────────────────────────────────

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        // Top progress bar
        _buildTopProgressBar(),
        // Content
        Expanded(child: _buildPageContent()),
        // Buttons
        Padding(
          padding: const EdgeInsets.all(24),
          child: _buildNavButtons(),
        ),
      ],
    );
  }

  // ── Top progress bar (narrow) ──────────────────────────────────────────────

  Widget _buildTopProgressBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GastroLogo(compact: true),
              const Spacer(),
              Text(
                '${_currentStep + 1} / $_totalSteps',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _totalSteps,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.accent),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step indicators (vertical — wide layout) ───────────────────────────────

  List<Widget> _buildStepIndicators({required bool vertical}) {
    final steps = [
      ('Hoş geldiniz', Icons.waving_hand_rounded),
      ('Restoran Bilgileri', Icons.store_rounded),
      ('Masa Düzeni', Icons.table_bar_rounded),
      ('Hazır!', Icons.check_circle_rounded),
    ];

    return steps.asMap().entries.map((e) {
      final idx = e.key;
      final (label, icon) = e.value;
      final isDone = idx < _currentStep;
      final isActive = idx == _currentStep;

      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.green
                    : isActive
                        ? AppColors.accent
                        : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDone ? Icons.check_rounded : icon,
                size: 18,
                color: isDone || isActive
                    ? Colors.white
                    : AppColors.textDim,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.textPrimary
                      : isDone
                          ? AppColors.green
                          : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ── Page content (PageView) ───────────────────────────────────────────────

  Widget _buildPageContent() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildStep0Welcome(),
        _buildStep1RestaurantInfo(),
        _buildStep2TableSetup(),
        _buildStep3Complete(),
      ],
    );
  }

  // ── Step 0: Welcome ───────────────────────────────────────────────────────

  Widget _buildStep0Welcome() {
    return FadeTransition(
      opacity: _stepFade,
      child: SlideTransition(
        position: _stepSlide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GastroCore\'e\nHoş Geldiniz',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Restoranınızı birkaç dakikada hazır hale getirelim. '
                'Bu kurulum sihirbazı size temel ayarları yapılandırmanızda yardımcı olacak.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),
              // Feature highlights
              _buildFeatureRow(
                Icons.bolt_rounded,
                AppColors.yellow,
                'Hızlı Kurulum',
                '5 dakikadan kısa sürer',
              ),
              const SizedBox(height: 16),
              _buildFeatureRow(
                Icons.wifi_off_rounded,
                AppColors.accent,
                'Çevrimdışı Çalışır',
                'İnternet bağlantısı gerekmez',
              ),
              const SizedBox(height: 16),
              _buildFeatureRow(
                Icons.receipt_long_rounded,
                AppColors.green,
                'İsviçre Uyumlu',
                'QR fatura ve MWST / TVA / IVA desteği',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(
      IconData icon, Color color, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 1: Restaurant Info ───────────────────────────────────────────────

  Widget _buildStep1RestaurantInfo() {
    return FadeTransition(
      opacity: _stepFade,
      child: SlideTransition(
        position: _stepSlide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restoran Bilgileri',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bu bilgiler makbuzlarda ve raporlarda görünür.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              _buildLabel('Restoran Adı'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _restaurantNameCtrl,
                hint: 'ör. Pizzeria Bella Vita',
                icon: Icons.store_rounded,
              ),
              const SizedBox(height: 20),
              _buildLabel('Adres'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _restaurantAddressCtrl,
                hint: 'ör. Bahnhofstrasse 10, 8001 Zürich',
                icon: Icons.location_on_rounded,
              ),
              const SizedBox(height: 20),
              _buildLabel('Para Birimi'),
              const SizedBox(height: 8),
              _buildCurrencySelector(),
              const SizedBox(height: 20),
              _buildLabel('Ülke'),
              const SizedBox(height: 8),
              _buildCountrySelector(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 14,
            color: AppColors.textDim,
          ),
          prefixIcon: Icon(icon, size: 18, color: AppColors.textDim),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencySelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButton<String>(
        value: _selectedCurrency,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: AppColors.surfaceContainer,
        iconEnabledColor: AppColors.textSecondary,
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        items: _currencies.map((c) {
          return DropdownMenuItem(value: c, child: Text(c));
        }).toList(),
        onChanged: (v) => setState(() => _selectedCurrency = v ?? 'CHF'),
      ),
    );
  }

  Widget _buildCountrySelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButton<String>(
        value: _selectedCountry,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: AppColors.surfaceContainer,
        iconEnabledColor: AppColors.textSecondary,
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
        items: _countries.entries.map((e) {
          return DropdownMenuItem(value: e.key, child: Text(e.value));
        }).toList(),
        onChanged: (v) => setState(() => _selectedCountry = v ?? 'CH'),
      ),
    );
  }

  // ── Step 2: Table Setup ───────────────────────────────────────────────────

  Widget _buildStep2TableSetup() {
    return FadeTransition(
      opacity: _stepFade,
      child: SlideTransition(
        position: _stepSlide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masa Düzeni',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kat ve masa sayısını girin. Kurulumdan sonra değiştirebilirsiniz.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              _buildStepperRow(
                label: 'Kat Sayısı',
                value: _floorCount,
                min: 1,
                max: 10,
                icon: Icons.layers_rounded,
                onDecrement: () =>
                    setState(() => _floorCount = (_floorCount - 1).clamp(1, 10)),
                onIncrement: () =>
                    setState(() => _floorCount = (_floorCount + 1).clamp(1, 10)),
              ),
              const SizedBox(height: 20),
              _buildStepperRow(
                label: 'Kat Başına Masa',
                value: _tablesPerFloor,
                min: 1,
                max: 50,
                icon: Icons.table_bar_rounded,
                onDecrement: () => setState(
                    () => _tablesPerFloor = (_tablesPerFloor - 1).clamp(1, 50)),
                onIncrement: () => setState(
                    () => _tablesPerFloor = (_tablesPerFloor + 1).clamp(1, 50)),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(kRadiusMedium),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Toplam ${_floorCount * _tablesPerFloor} masa oluşturulacak.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required IconData icon,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Decrement
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: value > min ? onDecrement : null,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Increment
          _StepperButton(
            icon: Icons.add_rounded,
            onTap: value < max ? onIncrement : null,
          ),
        ],
      ),
    );
  }

  // ── Step 3: Complete ──────────────────────────────────────────────────────

  Widget _buildStep3Complete() {
    return FadeTransition(
      opacity: _stepFade,
      child: SlideTransition(
        position: _stepSlide,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.greenDim,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 44,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Hazırsınız!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'GastroCore POS kullanıma hazır.\n'
                'İlk vardiyayı açmak için giriş yapın.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),
              _buildSummaryItem(
                Icons.store_rounded,
                _restaurantNameCtrl.text.isNotEmpty
                    ? _restaurantNameCtrl.text
                    : 'Restoran',
              ),
              const SizedBox(height: 12),
              _buildSummaryItem(
                Icons.table_bar_rounded,
                '$_floorCount kat · ${_floorCount * _tablesPerFloor} masa',
              ),
              const SizedBox(height: 12),
              _buildSummaryItem(
                Icons.monetization_on_rounded,
                _selectedCurrency,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigation buttons ────────────────────────────────────────────────────

  Widget _buildNavButtons() {
    final isLast = _currentStep == _totalSteps - 1;

    return Row(
      children: [
        if (_currentStep > 0) ...[
          Expanded(
            child: PosGhostButton(
              label: 'Geri',
              icon: Icons.arrow_back_rounded,
              onPressed: () async {
                await _stepAnimController.reverse();
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
                setState(() => _currentStep--);
                _stepAnimController.forward();
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: PosGradientButton(
            label: isLast ? 'Giriş Yap' : 'Devam Et',
            icon: isLast ? Icons.login_rounded : Icons.arrow_forward_rounded,
            onPressed: _nextStep,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stepper button
// ---------------------------------------------------------------------------

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null
          ? AppColors.surfaceContainerHigh
          : AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accent.withValues(alpha: 0.1),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: onTap != null ? AppColors.textPrimary : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact GastroCore logo for top bars
// ---------------------------------------------------------------------------

class _GastroLogo extends StatelessWidget {
  const _GastroLogo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryContainer],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'GastroCore',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryContainer],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'G',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'GastroCore',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const Text(
          'POS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textDim,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
