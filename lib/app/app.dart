import 'package:flutter/material.dart';

import '../domain/models/product.dart';
import '../domain/models/question.dart';
import '../domain/models/recommendation_result.dart';
import '../domain/repositories/catalog_repository.dart';
import '../services/analytics_service.dart';
import '../services/whatsapp_link_service.dart';
import 'app_config.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class BeautyAdvisorApp extends StatefulWidget {
  const BeautyAdvisorApp({
    required this.repository,
    required this.analytics,
    super.key,
  });

  final CatalogRepository repository;
  final AnalyticsService analytics;

  @override
  State<BeautyAdvisorApp> createState() => _BeautyAdvisorAppState();
}

class _BeautyAdvisorAppState extends State<BeautyAdvisorApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      repository: widget.repository,
      analytics: widget.analytics,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'oBoticario Belleza a tu Medida',
    theme: AppTheme.light,
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _AppShell(controller: controller),
    ),
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const _PhoneFrame(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (controller.error != null) {
      return _PhoneFrame(
        child: Scaffold(
          body: _PageFrame(
            child: _MessageCard(
              icon: Icons.cloud_off_outlined,
              title: 'No pudimos abrir el catálogo',
              message: controller.error!,
              action: FilledButton.icon(
                onPressed: () => _reload(context),
                icon: const Icon(Icons.refresh),
                label: const Text('Recargar aplicación'),
              ),
            ),
          ),
        ),
      );
    }

    final canGoBack =
        controller.stage == AppStage.categories ||
        controller.stage == AppStage.questionnaire;
    return _PhoneFrame(
      child: Scaffold(
        appBar: controller.stage == AppStage.welcome
            ? null
            : AppBar(
                backgroundColor: AppTheme.background,
                title: const Text('Belleza a tu Medida'),
                leading: canGoBack
                    ? IconButton(
                        tooltip: 'Volver',
                        onPressed: controller.back,
                        icon: const Icon(Icons.arrow_back),
                      )
                    : null,
                actions: [
                  IconButton(
                    tooltip: 'Volver a empezar',
                    onPressed: () => _confirmRestart(context),
                    icon: const Icon(Icons.restart_alt),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: switch (controller.stage) {
          AppStage.welcome => _WelcomeScreen(controller: controller),
          AppStage.categories => _CategoryScreen(controller: controller),
          AppStage.questionnaire => _QuestionScreen(controller: controller),
          AppStage.processing => const _ProcessingScreen(),
          AppStage.result => _ResultScreen(controller: controller),
        },
      ),
    );
  }

  void _reload(BuildContext context) {
    final uri = Uri.base;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: _PageFrame(
            child: _MessageCard(
              icon: Icons.refresh,
              title: 'Recarga necesaria',
              message: 'Actualiza esta pestaña para volver a cargar $uri.',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Volver a empezar?'),
        content: const Text('Se borrarán las respuestas de este recorrido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) controller.restart();
  }
}

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => _VisualBackground(
    prominent: true,
    child: _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 220),
          Card(
            color: const Color(0xF7FFFBF4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Belleza a tu medida',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.green,
                      fontSize: 34,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Encuentra los productos ideales para ti en solo 2 minutos.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const _Benefit(
                    icon: Icons.favorite_border,
                    text: 'Recomendación personalizada.',
                  ),
                  const _Benefit(
                    icon: Icons.format_list_numbered,
                    text: 'Solo 5 preguntas.',
                  ),
                  const _Benefit(
                    icon: Icons.support_agent,
                    text: 'Acompañamiento de un asesor.',
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Te acompaña ${AppConfig.advisorName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: controller.begin,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Comenzar mi diagnóstico'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppConfig.independentAdvisorNotice,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF465B54)),
          ),
        ],
      ),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 21, color: AppTheme.gold),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _CategoryScreen extends StatelessWidget {
  const _CategoryScreen({required this.controller});

  final AppController controller;

  static const categories = [
    ('perfumeria', 'Perfumería', Icons.local_florist_outlined),
    ('corporal', 'Cuidado corporal', Icons.self_improvement_outlined),
    ('facial', 'Cuidado facial', Icons.face_retouching_natural_outlined),
    ('cabello', 'Cabello', Icons.content_cut_outlined),
    ('regalos', 'Regalos y kits', Icons.card_giftcard_outlined),
  ];

  @override
  Widget build(BuildContext context) => _VisualBackground(
    child: _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Qué quieres descubrir?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Elige una categoría. Solo te haremos cinco preguntas.'),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: columns == 1 ? 3.4 : 2.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final category in categories)
                    Semantics(
                      button: true,
                      label: 'Elegir ${category.$2}',
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => controller.selectCategory(category.$1),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppTheme.softBlue,
                                  child: Icon(
                                    category.$3,
                                    color: AppTheme.blue,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    category.$2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _QuestionScreen extends StatelessWidget {
  const _QuestionScreen({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final question = controller.currentQuestion;
    if (question == null) {
      return const _PageFrame(
        child: _MessageCard(
          icon: Icons.warning_amber,
          title: 'Ruta no disponible',
          message: 'Esta categoría no tiene preguntas configuradas.',
        ),
      );
    }
    final current = controller.questionIndex + 1;
    final selected = controller.answers[question.id];
    return _VisualBackground(
      child: _PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pregunta $current de 5',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.green,
              ),
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Progreso: pregunta $current de 5',
              child: LinearProgressIndicator(value: current / 5),
            ),
            const SizedBox(height: 30),
            Text(
              question.text,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            for (final option in question.options) ...[
              _AnswerCard(
                option: option,
                selected: selected == option.id,
                onTap: () => controller.selectAnswer(option),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: selected == null ? null : controller.continueQuestion,
              child: Text(current == 5 ? 'Ver mi recomendación' : 'Continuar'),
            ),
            if (current > 1) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: controller.back,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Atrás'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessingScreen extends StatelessWidget {
  const _ProcessingScreen();

  @override
  Widget build(BuildContext context) => _VisualBackground(
    child: _PageFrame(
      child: Card(
        color: const Color(0xF7FFFBF4),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Estamos encontrando tu mejor opción',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Analizamos tus respuestas para encontrar opciones acordes con lo que buscas.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AnswerOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppTheme.softBlue : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppTheme.blue : const Color(0xFFD8E5E1),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          child: Row(
            children: [
              Expanded(child: Text(option.label)),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppTheme.blue : const Color(0xFF71817C),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ResultScreen extends StatefulWidget {
  const _ResultScreen({required this.controller});

  final AppController controller;

  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<_ResultScreen> {
  Product? selectedProduct;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    if (result == null || !result.hasMatch) {
      return _PageFrame(
        child: _MessageCard(
          icon: Icons.support_agent,
          title: 'Prefiero orientarte personalmente',
          message:
              'No encontré una opción que respete todos tus criterios. '
              'No voy a forzar una recomendación incoherente.',
          action: _AdvisorButton(controller: controller),
          secondary: OutlinedButton.icon(
            onPressed: controller.restart,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Volver a empezar'),
          ),
        ),
      );
    }
    final primary = result.primary!;
    return _VisualBackground(
      child: _PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.auto_awesome, size: 46, color: AppTheme.green),
            const SizedBox(height: 10),
            Text(
              'Tu recomendación principal',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 22),
            _ProductCard(
              ranked: primary,
              primary: true,
              selected: selectedProduct?.id == primary.product.id,
              onSelect: () => _selectProduct(primary.product),
            ),
            if (result.alternative != null) ...[
              const SizedBox(height: 22),
              Text(
                'Otra opción para ti',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              _ProductCard(
                ranked: result.alternative!,
                primary: false,
                selected: selectedProduct?.id == result.alternative!.product.id,
                onSelect: () => _selectProduct(result.alternative!.product),
              ),
            ],
            if (selectedProduct != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _showRequest(context, selectedProduct!),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuar con mi elección'),
              ),
            ],
            const SizedBox(height: 10),
            _AdvisorButton(controller: controller),
            if (!AppConfig.whatsappConfigured) ...[
              const SizedBox(height: 10),
              const Text(
                'WhatsApp pendiente de configurar. Ejecuta la app con '
                '--dart-define=WHATSAPP_NUMBER=57XXXXXXXXXX.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A4E00)),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.restart,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Volver a empezar'),
            ),
            const SizedBox(height: 18),
            Text(
              AppConfig.independentAdvisorNotice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _selectProduct(Product product) {
    setState(() => selectedProduct = product);
  }

  Future<void> _showRequest(BuildContext context, Product product) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final whatsappController = TextEditingController();
    var showSummary = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                22,
                22,
                22,
                22 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: _RequestContent(
                product: product,
                nameController: nameController,
                whatsappController: whatsappController,
                showSummary: showSummary,
                onReview: () {
                  if (formKey.currentState!.validate()) {
                    setSheetState(() => showSummary = true);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
    nameController.dispose();
    whatsappController.dispose();
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.ranked,
    required this.primary,
    required this.selected,
    required this.onSelect,
  });

  final RankedProduct ranked;
  final bool primary;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final product = ranked.product;
    return Card(
      color: primary ? const Color(0xFFF0F8F5) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected ? AppTheme.gold : const Color(0xFFE6D9C5),
          width: selected ? 3 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductImage(product: product),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.isSuggestedKit)
                        const Text(
                          'PROPUESTA SUGERIDA · NO ES SKU OFICIAL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.blue,
                          ),
                        ),
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${product.presentation} · Código ${product.code}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              priceLabel(product.priceCop),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.green,
              ),
            ),
            Text(
              AppConfig.priceIsCurrent
                  ? 'Precio de referencia · Ciclo 08, agosto de 2026'
                  : 'Catálogo vencido · Consulta precio vigente',
            ),
            Text('Disponibilidad revisada: ${product.updated}'),
            const SizedBox(height: 16),
            if (product.familyOrActive.isNotEmpty) ...[
              Text(
                product.familyOrActive,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.green,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              '¿Por qué es ideal para ti?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final reason in ranked.reasons.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.check_circle,
                        size: 17,
                        color: AppTheme.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onSelect,
              icon: Icon(selected ? Icons.check_circle : Icons.favorite_border),
              label: Text(
                selected
                    ? 'Producto seleccionado'
                    : 'Me interesa este producto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String priceLabel(int value) {
    final digits = value.toString();
    final buffer = StringBuffer(r'$');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return '${buffer.toString()} COP';
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 360;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: compact ? 110 : 120,
        height: compact ? 140 : 150,
        color: Colors.white,
        child: Image.asset(
          product.resolvedImagePath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: AppTheme.softBlue,
            child: Icon(
              product.isSuggestedKit ? Icons.card_giftcard : Icons.spa_outlined,
              color: AppTheme.blue,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvisorButton extends StatelessWidget {
  const _AdvisorButton({required this.controller});

  final AppController controller;
  static const whatsapp = WhatsAppLinkService();

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => _showHelp(context),
    icon: const Icon(Icons.support_agent),
    label: const Text('Quiero asesoría'),
  );

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Necesitas ayuda?'),
        content: const Text(
          'Escríbenos por WhatsApp.\n\nTu asesor te atenderá lo más pronto posible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: AppConfig.whatsappConfigured
                ? () {
                    Navigator.pop(dialogContext);
                    _open(context);
                  }
                : null,
            child: const Text('Continuar a WhatsApp'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await controller.recordWhatsappClick(null);
    final opened = await whatsapp.launch(whatsapp.buildAdvisorUri());
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible abrir WhatsApp.')),
      );
    }
  }
}

class _RequestContent extends StatelessWidget {
  const _RequestContent({
    required this.product,
    required this.nameController,
    required this.whatsappController,
    required this.showSummary,
    required this.onReview,
  });

  final Product product;
  final TextEditingController nameController;
  final TextEditingController whatsappController;
  final bool showSummary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        showSummary ? 'Resumen de tu solicitud' : 'Tus datos',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      if (!showSummary) ...[
        TextFormField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ingresa tu nombre.'
              : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: whatsappController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número de WhatsApp',
            hintText: 'Ejemplo: 573001234567',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final normalized = _normalizePhone(value ?? '');
            if (normalized.isEmpty) return 'Ingresa tu número de WhatsApp.';
            if (!RegExp(r'^\d{8,15}$').hasMatch(normalized)) {
              return 'Usa entre 8 y 15 dígitos, incluido el código del país.';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onReview,
          child: const Text('Revisar mi solicitud'),
        ),
      ] else ...[
        _SummaryRow(label: 'Cliente', value: nameController.text.trim()),
        _SummaryRow(
          label: 'WhatsApp',
          value: _normalizePhone(whatsappController.text),
        ),
        _SummaryRow(label: 'Producto', value: product.name),
        _SummaryRow(label: 'Presentación', value: product.presentation),
        _SummaryRow(label: 'Código/SKU', value: product.code),
        const _SummaryRow(label: 'Cantidad', value: '1'),
        _SummaryRow(
          label: 'Precio',
          value: _ProductCard.priceLabel(product.priceCop),
        ),
        _SummaryRow(
          label: 'Subtotal',
          value: _ProductCard.priceLabel(product.priceCop),
        ),
        const _SummaryRow(label: 'Descuento', value: r'$0 COP'),
        const _SummaryRow(label: 'Entrega/envío', value: 'Por confirmar'),
        _SummaryRow(
          label: 'Total productos',
          value: _ProductCard.priceLabel(product.priceCop),
        ),
        const _SummaryRow(label: 'Asesor', value: AppConfig.advisorName),
        const _SummaryRow(label: 'Canal', value: 'No conectado'),
        const _SummaryRow(label: 'Campaña', value: 'No conectada'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Enviar mi solicitud'),
        ),
        const SizedBox(height: 10),
        const Text(
          'La creación directa del pedido no está disponible en esta versión local del repositorio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF7A4E00)),
        ),
      ],
    ],
  );

  static String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _VisualBackground extends StatelessWidget {
  const _VisualBackground({required this.child, this.prominent = false});
  final Widget child;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: AppTheme.background),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: prominent ? 245 : 220,
        child: Image.asset(
          'assets/images/primera_pantalla.jpeg',
          alignment: Alignment.topCenter,
          fit: BoxFit.cover,
          opacity: AlwaysStoppedAnimation(prominent ? 1 : 0.14),
        ),
      ),
      Positioned.fill(
        child: ColoredBox(
          color: prominent ? const Color(0x0DFFFBF4) : const Color(0x80FFFBF4),
        ),
      ),
      child,
    ],
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    ),
  );
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  static const double phoneType2Width = 390;
  static const double phoneType2Height = 844;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // On a real phone, or in the compact Chrome window opened by
      // run_phone_2.ps1, the app uses the whole viewport. On desktop it is
      // always presented inside the approved Phone Type 2 frame.
      if (constraints.maxWidth <= 480) return child;
      final availableHeight = constraints.maxHeight - 32;
      final phoneHeight = availableHeight > phoneType2Height
          ? phoneType2Height
          : availableHeight;
      return ColoredBox(
        color: const Color(0xFFDDEBE7),
        child: Center(
          child: Container(
            width: phoneType2Width,
            height: phoneHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: const Color(0xFFB8CEC7), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330B3329),
                  blurRadius: 32,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 48, color: AppTheme.blue),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 22), action!],
          if (secondary != null) ...[const SizedBox(height: 10), secondary!],
        ],
      ),
    ),
  );
}
