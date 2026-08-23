import 'package:flutter/material.dart';

import '../domain/models/product.dart';
import '../domain/models/question.dart';
import '../domain/models/recommendation_result.dart';
import '../domain/models/cross_sell_result.dart';
import '../domain/models/attribution_context.dart';
import '../domain/colombian_mobile_number.dart';
import '../domain/models/customer_draft.dart';
import '../domain/models/order.dart';
import '../domain/models/order_selection.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/cross_sell_repository.dart';
import '../domain/repositories/order_repository.dart';
import '../services/analytics_service.dart';
import '../services/whatsapp_link_service.dart';
import 'app_config.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class BeautyAdvisorApp extends StatefulWidget {
  const BeautyAdvisorApp({
    required this.repository,
    required this.crossSellRepository,
    required this.orderRepository,
    required this.analytics,
    super.key,
  });

  final CatalogRepository repository;
  final CrossSellRepository crossSellRepository;
  final OrderRepository? orderRepository;
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
      crossSellRepository: widget.crossSellRepository,
      orderRepository: widget.orderRepository,
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
    // La categoría conservada visualmente es funcionalmente la pregunta 1.
    final current = controller.questionIndex + 2;
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
            if (current > 2) ...[
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
  OrderSelection? orderSelection;
  CrossSellResult crossSell = const CrossSellResult([]);

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
            if (controller.wheelCampaignActive) ...[
              const SizedBox(height: 18),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.card_giftcard, color: AppTheme.green),
                    title: Text('Tienes un beneficio especial'),
                    subtitle: Text(
                      'Elige tu producto y antes de enviar tu solicitud podrás descubrir tu beneficio de Amor y Amistad.',
                    ),
                  ),
                ),
              ),
            ],
            if (selectedProduct != null && crossSell.candidates.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'Completa tu elección',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final candidate in crossSell.candidates)
                _ComplementaryCard(
                  candidate: candidate,
                  selected:
                      orderSelection?.containsComplementary(
                        candidate.product.id,
                      ) ==
                      true,
                  onChanged: () => _toggleComplementary(candidate),
                ),
            ],
            if (selectedProduct != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _showRequest(context, orderSelection!),
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
    final nextSelection = OrderSelection.fromPrimary(product);
    final nextCrossSell = controller.crossSellFor(product);
    setState(() {
      selectedProduct = product;
      orderSelection = nextSelection;
      crossSell = nextCrossSell;
    });
    for (final candidate in nextCrossSell.candidates) {
      controller.recordCrossSellShown(candidate);
    }
  }

  void _toggleComplementary(CrossSellCandidate candidate) {
    final selection = orderSelection!;
    final added = !selection.containsComplementary(candidate.product.id);
    setState(() {
      if (added) {
        selection.addComplementary(
          candidate.product,
          relationId: candidate.relation.id,
        );
      } else {
        selection.removeComplementary(candidate.product.id);
      }
    });
    controller.recordComplementaryChanged(candidate: candidate, added: added);
  }

  Future<void> _showRequest(
    BuildContext context,
    OrderSelection selection,
  ) async {
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
                selection: selection,
                product: controller.products.firstWhere(
                  (item) => item.id == selection.primary.productId,
                ),
                attribution: controller.attribution,
                nameController: nameController,
                whatsappController: whatsappController,
                showSummary: showSummary,
                orderSubmissionConfigured: controller.orderSubmissionConfigured,
                wheelCampaignActive: controller.wheelCampaignActive,
                onReview: () {
                  if (formKey.currentState!.validate()) {
                    setSheetState(() => showSummary = true);
                  }
                },
                onSubmit: () async {
                  final created = await controller.createOrder(
                    customer: CustomerDraft(
                      name: nameController.text,
                      whatsapp: whatsappController.text,
                      acceptsDataProcessing: true,
                      acceptsPromotions: false,
                    ),
                    selection: selection,
                  );
                  return created;
                },
                onSpin: () => controller.spinWheel(
                  customer: CustomerDraft(
                    name: nameController.text,
                    whatsapp: whatsappController.text,
                    acceptsDataProcessing: true,
                    acceptsPromotions: false,
                  ),
                  selection: selection,
                ),
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

class _ComplementaryCard extends StatelessWidget {
  const _ComplementaryCard({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final CrossSellCandidate candidate;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final product = candidate.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductImage(product: product),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(product.presentation),
                      const SizedBox(height: 8),
                      Text(
                        _ProductCard.priceLabel(product.priceCop),
                        style: const TextStyle(
                          color: AppTheme.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(candidate.relation.benefit),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onChanged,
              icon: Icon(selected ? Icons.remove_circle_outline : Icons.add),
              label: Text(
                selected ? 'Quitar complemento' : 'Agregar complemento',
              ),
            ),
          ],
        ),
      ),
    );
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

class _RequestContent extends StatefulWidget {
  const _RequestContent({
    required this.selection,
    required this.product,
    required this.attribution,
    required this.nameController,
    required this.whatsappController,
    required this.showSummary,
    required this.orderSubmissionConfigured,
    required this.wheelCampaignActive,
    required this.onReview,
    required this.onSubmit,
    required this.onSpin,
  });

  final OrderSelection selection;
  final Product product;
  final AttributionContext attribution;
  final TextEditingController nameController;
  final TextEditingController whatsappController;
  final bool showSummary;
  final bool orderSubmissionConfigured;
  final bool wheelCampaignActive;
  final VoidCallback onReview;
  final Future<CreatedOrder> Function() onSubmit;
  final Future<WheelBenefit> Function() onSpin;

  @override
  State<_RequestContent> createState() => _RequestContentState();
}

class _RequestContentState extends State<_RequestContent> {
  bool acceptsDataProcessing = false;
  bool submitting = false;
  CreatedOrder? createdOrder;
  String? submissionError;
  bool spinning = false;
  WheelBenefit? wheelBenefit;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        createdOrder != null
            ? 'Solicitud recibida'
            : widget.showSummary
            ? 'Resumen de tu solicitud'
            : 'Tus datos',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      if (createdOrder != null) ...[
        const Icon(Icons.check_circle, size: 56, color: AppTheme.green),
        const SizedBox(height: 12),
        const Text(
          'Tu solicitud fue creada correctamente.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Número', value: createdOrder!.number),
        const _SummaryRow(label: 'Estado', value: 'Solicitado'),
      ] else if (!widget.showSummary) ...[
        TextFormField(
          controller: widget.nameController,
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
          controller: widget.whatsappController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número de WhatsApp',
            hintText: 'Ejemplo: 573001234567',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final normalized = ColombianMobileNumber.normalize(value ?? '');
            if (normalized.isEmpty) return 'Ingresa tu número de WhatsApp.';
            return null;
          },
        ),
        const SizedBox(height: 8),
        FormField<bool>(
          initialValue: false,
          validator: (value) =>
              value == true ? null : 'Debes autorizar el tratamiento de datos.',
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: acceptsDataProcessing,
                onChanged: (value) {
                  setState(() => acceptsDataProcessing = value ?? false);
                  field.didChange(value ?? false);
                },
                title: const Text(
                  'Autorizo el tratamiento de mis datos para gestionar esta solicitud.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (field.hasError)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    field.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: widget.onReview,
          child: const Text('Revisar mi solicitud'),
        ),
      ] else ...[
        _SummaryRow(label: 'Cliente', value: widget.nameController.text.trim()),
        _SummaryRow(
          label: 'WhatsApp',
          value: ColombianMobileNumber.normalize(
            widget.whatsappController.text,
          ),
        ),
        _SummaryRow(label: 'Producto', value: widget.product.name),
        _SummaryRow(label: 'Presentación', value: widget.product.presentation),
        _SummaryRow(label: 'Código/SKU', value: widget.product.code),
        const _SummaryRow(label: 'Cantidad', value: '1'),
        _SummaryRow(
          label: 'Precio',
          value: _ProductCard.priceLabel(widget.product.priceCop),
        ),
        for (final item in widget.selection.complementaries)
          _SummaryRow(
            label: 'Complemento',
            value:
                '${item.productName} · ${_ProductCard.priceLabel(item.originalUnitPriceCop)}',
          ),
        _SummaryRow(
          label: 'Productos',
          value: _ProductCard.priceLabel(
            wheelBenefit?.productsCop ?? widget.selection.amounts.subtotalCop,
          ),
        ),
        if (wheelBenefit != null) ...[
          _SummaryRow(
            label:
                'Descuento Amor y Amistad (${wheelBenefit!.discountPercent}%)',
            value: '-${_ProductCard.priceLabel(wheelBenefit!.discountCop)}',
          ),
          _SummaryRow(
            label: 'Venta neta de productos',
            value: _ProductCard.priceLabel(wheelBenefit!.netProductsCop),
          ),
        ] else if (!widget.wheelCampaignActive)
          const _SummaryRow(label: 'Descuento', value: r'$0 COP'),
        const _SummaryRow(label: 'Entrega/envío', value: 'Por confirmar'),
        _SummaryRow(
          label: 'TOTAL',
          value: _ProductCard.priceLabel(
            wheelBenefit?.netProductsCop ?? widget.selection.amounts.totalCop,
          ),
        ),
        const _SummaryRow(label: 'Asesor', value: AppConfig.advisorName),
        _SummaryRow(label: 'Canal', value: widget.attribution.channelId),
        _SummaryRow(
          label: 'Campaña',
          value: widget.attribution.campaignId ?? 'Sin campaña',
        ),
        const SizedBox(height: 20),
        if (widget.wheelCampaignActive && wheelBenefit == null) ...[
          const Text(
            '¡Es momento de descubrir tu beneficio!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: spinning ? null : _spin,
            icon: const Icon(Icons.casino_outlined),
            label: Text(spinning ? 'Girando…' : 'Girar ruleta'),
          ),
          const SizedBox(height: 12),
        ] else if (wheelBenefit != null) ...[
          Text(
            '¡Ganaste ${wheelBenefit!.discountPercent}% de descuento!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.green,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed:
              widget.orderSubmissionConfigured &&
                  !submitting &&
                  (!widget.wheelCampaignActive || wheelBenefit != null)
              ? _submit
              : null,
          icon: const Icon(Icons.send_outlined),
          label: Text(submitting ? 'Enviando…' : 'Enviar mi solicitud'),
        ),
        if (!widget.orderSubmissionConfigured) ...[
          const SizedBox(height: 10),
          const Text(
            'Supabase Local no está configurado para esta ejecución.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7A4E00)),
          ),
        ],
        if (submissionError != null) ...[
          const SizedBox(height: 10),
          Text(
            submissionError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ],
  );

  Future<void> _submit() async {
    setState(() {
      submitting = true;
      submissionError = null;
    });
    try {
      final order = await widget.onSubmit();
      if (mounted) setState(() => createdOrder = order);
    } catch (error) {
      if (mounted) {
        setState(
          () => submissionError = 'No fue posible crear la solicitud: $error',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _spin() async {
    setState(() {
      spinning = true;
      submissionError = null;
    });
    try {
      final benefit = await widget.onSpin();
      if (mounted) setState(() => wheelBenefit = benefit);
    } catch (error) {
      if (mounted) {
        setState(() => submissionError = 'No fue posible girar: $error');
      }
    } finally {
      if (mounted) setState(() => spinning = false);
    }
  }
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
