import 'dart:math' as math;

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
import '../domain/repositories/staff_repository.dart';
import '../services/analytics_service.dart';
import '../services/whatsapp_link_service.dart';
import 'app_config.dart';
import 'app_controller.dart';
import 'app_theme.dart';
import 'staff_app.dart';

class BeautyAdvisorApp extends StatefulWidget {
  const BeautyAdvisorApp({
    required this.repository,
    required this.crossSellRepository,
    required this.orderRepository,
    this.staffRepository,
    required this.analytics,
    super.key,
  });

  final CatalogRepository repository;
  final CrossSellRepository crossSellRepository;
  final OrderRepository? orderRepository;
  final StaffRepository? staffRepository;
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
      builder: (context, _) => _AppShell(
        controller: controller,
        staffRepository: widget.staffRepository,
      ),
    ),
  );
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.controller, required this.staffRepository});

  final AppController controller;
  final StaffRepository? staffRepository;

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
    if (!controller.availabilityVerified) {
      return _PhoneFrame(
        child: Scaffold(
          body: _PageFrame(
            child: _MessageCard(
              icon: Icons.inventory_2_outlined,
              title: 'Disponibilidad temporal',
              message:
                  controller.availabilityError ??
                  'Estamos verificando la disponibilidad de nuestros productos. Puedes intentar nuevamente o pedir asesoría.',
              action: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await controller.retryAvailability();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 10),
                  _AdvisorButton(controller: controller),
                ],
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
          AppStage.welcome => _WelcomeScreen(
            controller: controller,
            staffRepository: staffRepository,
          ),
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
  const _WelcomeScreen({
    required this.controller,
    required this.staffRepository,
  });

  final AppController controller;
  final StaffRepository? staffRepository;

  @override
  Widget build(BuildContext context) => _VisualBackground(
    prominent: true,
    child: _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  key: const Key('temporary-staff-access'),
                  tooltip: 'Gestión de pedidos',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.green,
                    minimumSize: const Size(52, 52),
                    side: const BorderSide(
                      color: AppTheme.green,
                      width: 2,
                    ),
                    elevation: 4,
                    shadowColor: Colors.black26,
                  ),
                  icon: const Icon(
                    Icons.admin_panel_settings,
                    size: 30,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StaffApp(repository: staffRepository),
                    ),
                  ),
                ),
              ),
          ),
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
 
        const SizedBox(height: 14),

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
            for (final option in controller.currentQuestionOptions) ...[
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
            if (result.confidence == RecommendationConfidence.low) ...[
              const SizedBox(height: 12),
              const Text(
                'Esta es la opción que más se acerca a lo que buscas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'No encontramos una coincidencia exacta con todas tus preferencias, pero esta es la alternativa más cercana dentro del catálogo disponible.',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            _ProductCard(
              ranked: primary,
              primary: true,
              immediateDelivery: controller.hasImmediateStock(
                primary.product.code,
              ),
              selected: _isSelected(primary.product),
              onSelect: () => _toggleProduct(primary.product),
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
                immediateDelivery: controller.hasImmediateStock(
                  result.alternative!.product.code,
                ),
                selected: _isSelected(result.alternative!.product),
                onSelect: () => _toggleProduct(result.alternative!.product),
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
            if (orderSelection != null && crossSell.candidates.isNotEmpty) ...[
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
            if (orderSelection != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _showDeliveryNextStep(),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuar con mi selección'),
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

  bool _isSelected(Product product) =>
      orderSelection?.items.any((item) => item.productId == product.id) == true;

  void _toggleProduct(Product product) {
    
    final result = controller.result!;
    final recommendedPrimary = result.primary!.product;
    final recommendedAlternative = result.alternative?.product;

    var primarySelected = _isSelected(recommendedPrimary);
    var alternativeSelected =
        recommendedAlternative != null && _isSelected(recommendedAlternative);

    if (product.id == recommendedPrimary.id) {
      primarySelected = !primarySelected;
    } else if (recommendedAlternative != null &&
        product.id == recommendedAlternative.id) {
      alternativeSelected = !alternativeSelected;
    }

    if (!primarySelected && !alternativeSelected) {
      setState(() {
        orderSelection = null;
        crossSell = const CrossSellResult([]);
      });
      return;
    }

    final baseProduct = primarySelected
        ? recommendedPrimary
        : recommendedAlternative!;

    final nextSelection = OrderSelection.fromPrimary(baseProduct);

    if (primarySelected && alternativeSelected) {
      nextSelection.addAlternative(recommendedAlternative!);
    }

    final nextCrossSell = controller.crossSellFor(baseProduct);

    setState(() {
      orderSelection = nextSelection;
      crossSell = nextCrossSell;
    });

    for (final candidate in nextCrossSell.candidates) {
      controller.recordCrossSellShown(candidate);
    }
    
  }

  Future<void> _showDeliveryNextStep() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('¡Excelente elección!'),
        content: const Text(
          'Ya elegiste tus productos.\n'
          'Ahora dinos cómo quieres recibir tu pedido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Atrás'),
          ),
          FilledButton(
            key: const Key('continue-to-delivery'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (proceed == true && mounted && orderSelection != null) {
      await _showRequest(context, orderSelection!);
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
    final scrollController = ScrollController();
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
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                22,
                22,
                22,
                22 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: _RequestContent(
                selection: selection,
                products: controller.products,
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
                onSubmit: (requiresDelivery, deliveryDetails) async {
                  final created = await controller.createOrder(
                    customer: CustomerDraft(
                      name: nameController.text,
                      whatsapp: whatsappController.text,
                      city: deliveryDetails?.city,
                      acceptsDataProcessing: true,
                      acceptsPromotions: false,
                    ),
                    selection: selection,
                    requiresDelivery: requiresDelivery,
                    deliveryDetails: deliveryDetails,
                  );

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (scrollController.hasClients) {
                      scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                      );
                    }
                  });

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
                onContinueWhatsApp: (order, deliveryLabel) async {
                  await controller.recordWhatsappClick(
                    selection.primary.productId,
                  );
                  const service = WhatsAppLinkService();
                  final opened = await service.launch(
                    service.buildOrderUri(
                      orderNumber: order.number,
                      customerName: nameController.text.trim(),
                      productNames: selection.items.map(
                        (item) => item.productName,
                      ),
                      deliveryMethod: deliveryLabel,
                    ),
                  );
                  if (!opened && sheetContext.mounted) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('No fue posible abrir WhatsApp.'),
                      ),
                    );
                  }
                },
                onNewPurchase: () {
                  Navigator.pop(sheetContext);
                  controller.startNewPurchase();
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
    required this.immediateDelivery,
    required this.selected,
    required this.onSelect,
  });

  final RankedProduct ranked;
  final bool primary;
  final bool immediateDelivery;
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
            if (immediateDelivery) ...[
              const SizedBox(height: 10),
              Chip(
                key: ValueKey('immediate-delivery-${product.code}'),
                avatar: const Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: AppTheme.green,
                ),
                label: const Text('Entrega inmediata'),
                backgroundColor: const Color(0xFFE8F5EE),
                side: const BorderSide(color: Color(0xFFB8DCC9)),
                labelStyle: const TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
    required this.products,
    required this.attribution,
    required this.nameController,
    required this.whatsappController,
    required this.showSummary,
    required this.orderSubmissionConfigured,
    required this.wheelCampaignActive,
    required this.onReview,
    required this.onSubmit,
    required this.onSpin,
    required this.onContinueWhatsApp,
    required this.onNewPurchase,
  });

  final OrderSelection selection;
  final List<Product> products;
  final AttributionContext attribution;
  final TextEditingController nameController;
  final TextEditingController whatsappController;
  final bool showSummary;
  final bool orderSubmissionConfigured;
  final bool wheelCampaignActive;
  final VoidCallback onReview;
  final Future<CreatedOrder> Function(
    bool requiresDelivery,
    DeliveryDetails? deliveryDetails,
  )
  onSubmit;
  final Future<WheelBenefit> Function() onSpin;
  final Future<void> Function(CreatedOrder order, String deliveryLabel)
  onContinueWhatsApp;
  final VoidCallback onNewPurchase;

  @override
  State<_RequestContent> createState() => _RequestContentState();
}

class _RequestContentState extends State<_RequestContent>
    with SingleTickerProviderStateMixin {
  bool acceptsDataProcessing = false;
  bool submitting = false;
  CreatedOrder? createdOrder;
  String? submissionError;
  bool spinning = false;
  WheelBenefit? wheelBenefit;
  WheelBenefit? spinningBenefit;
  bool? requiresDelivery;
  final cityController = TextEditingController();
  final addressController = TextEditingController();
  final neighborhoodController = TextEditingController();
  final recipientController = TextEditingController();
  final directionsController = TextEditingController();
  late final AnimationController _wheelController;

  @override
  void initState() {
    super.initState();
    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _wheelController.dispose();
    cityController.dispose();
    addressController.dispose();
    neighborhoodController.dispose();
    recipientController.dispose();
    directionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        createdOrder != null
            ? '¡Solicitud recibida!'
            : widget.showSummary
            ? 'Resumen de tu solicitud'
            : 'Tu solicitud',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      if (createdOrder != null) ...[
        const Icon(Icons.check_circle, size: 62, color: AppTheme.green),
        const SizedBox(height: 12),
        const Text(
          'Tu selección quedó registrada correctamente.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          key: const Key('final-order-number'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1DFC0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              const Text(
                'SOLICITUD',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                createdOrder!.number,
                style: const TextStyle(
                  color: AppTheme.green,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Guarda este número para consultar tu solicitud.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _FinalInfoCard(
          icon: Icons.people_alt_outlined,
          title: 'TUS ASESORES',
          headline: AppConfig.advisorName,
          message:
              'Revisaremos los detalles de tu solicitud y coordinaremos contigo la entrega de tu pedido.',
        ),
        const SizedBox(height: 12),
        const _FinalInfoCard(
          icon: Icons.chat_outlined,
          title: '¿QUÉ SIGUE?',
          headline: 'Te contactaremos por WhatsApp',

          message:
              'Tu solicitud ya quedó registrada. Revisaremos los detalles de tu pedido y te contactaremos por WhatsApp en el menor tiempo posible.',
        ),
        const SizedBox(height: 12),

        const Text(
          'PRODUCTOS SOLICITADOS',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.green),
        ),
        const SizedBox(height: 8),
        for (final item in widget.selection.items) ...[
          _SummaryRow(
            label: 'Producto',
            value: '${item.productName} × ${item.quantity}',
          ),
        ],
        const SizedBox(height: 12),

        Card(
          color: const Color(0xFFFFFBF4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _SummaryRow(label: 'Entrega', value: _deliveryLabel),
                _SummaryRow(
                  label: 'Productos',
                  value: _ProductCard.priceLabel(
                    wheelBenefit?.productsCop ??
                        widget.selection.amounts.subtotalCop,
                  ),
                ),

                if (wheelBenefit != null)
                  _SummaryRow(
                    label: 'Descuento ${wheelBenefit!.discountPercent}%',
                    value:
                        '-${_ProductCard.priceLabel(wheelBenefit!.discountCop)}',
                    valueColor: AppTheme.green,
                  ),
                _SummaryRow(
                  label: 'Total',
                  value: _ProductCard.priceLabel(
                    wheelBenefit?.netProductsCop ??
                        widget.selection.amounts.totalCop,
                  ),
                  valueColor: AppTheme.green,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('final-whatsapp-button'),
          onPressed: AppConfig.whatsappConfigured
              ? () => widget.onContinueWhatsApp(createdOrder!, _deliveryLabel)
              : null,
          icon: const Icon(Icons.chat),
          label: const Text('Continuar por WhatsApp'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('new-purchase-button'),
          onPressed: widget.onNewPurchase,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Realizar otra compra'),
        ),
      ] else if (!widget.showSummary) ...[
        _deliverySection(),
        const SizedBox(height: 18),
        Text('Tus datos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        TextFormField(
          controller: widget.nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
          ),

          validator: (value) {
            final name = value?.trim() ?? '';

            if (name.isEmpty) {
              return 'Ingresa tu nombre.';
            }

            if (name.length < 3) {
              return 'Ingresa un nombre válido de al menos 3 caracteres.';
            }

            return null;
          },
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
          onPressed: () {
            if (!_deliveryIsComplete) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Selecciona el tipo de envío y completa los datos de entrega.'),
                ),
              );
              return;
            }
            widget.onReview();
          },
          child: const Text('Revisar mi solicitud'),
        ),
      ] else ...[
        if (widget.wheelCampaignActive) ...[
          Container(
            key: const Key('wheel-campaign-banner'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.green,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '🎁 Campaña Amor y Amistad 2026',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (wheelBenefit != null) ...[
          Container(
            key: const Key('wheel-benefit-banner'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6EF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFB7DCC7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.celebration, color: AppTheme.green, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '¡Felicidades! Ganaste ${wheelBenefit!.discountPercent}% de descuento',
                    style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.wheelCampaignActive && wheelBenefit == null) ...[
          if (spinningBenefit != null)
            _SpinningWheel(
              controller: _wheelController,
              targetPercent: spinningBenefit!.discountPercent,
            )
          else
            _ReadyWheel(onSpin: spinning ? null : _spin, waiting: spinning),
          const SizedBox(height: 16),
        ],
        for (final item in widget.selection.items) ...[
          _SummaryProductCard(item: item, product: _productFor(item.productId)),
          const SizedBox(height: 12),
        ],
        _SummaryRow(label: 'Tipo de envío', value: _deliveryLabel),
        const SizedBox(height: 14),
        _SummaryTotalsCard(
          subtotalCop:
              wheelBenefit?.productsCop ?? widget.selection.amounts.subtotalCop,
          discountPercent: wheelBenefit?.discountPercent,
          discountCop: wheelBenefit?.discountCop ?? 0,
          netProductsCop:
              wheelBenefit?.netProductsCop ?? widget.selection.amounts.totalCop,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('submit-order-button'),
          onPressed:
              widget.orderSubmissionConfigured &&
                  !submitting &&
                  _deliveryIsComplete &&
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

  Widget _deliverySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Último paso · Entrega',
        style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('Elige una opción para continuar con tu solicitud.'),
      const SizedBox(height: 8),
      Text(
        '¿Cómo quieres recibir tu pedido?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Column(
        children: [
          RadioListTile<bool>(
            value: true,
            groupValue: requiresDelivery,
            onChanged: spinning || submitting
                ? null
                : (value) => setState(() => requiresDelivery = value),
            title: const Text('Envío a domicilio'),
            subtitle: const Text('El costo del envío está por confirmar.'),
          ),
          RadioListTile<bool>(
            value: false,
            groupValue: requiresDelivery,
            onChanged: spinning || submitting
                ? null
                : (value) => setState(() => requiresDelivery = value),
            title: const Text('Acordar entrega con asesor'),
          ),
        ],
      ),
      if (requiresDelivery == true) ...[
        _DeliveryField(
          controller: cityController,
          label: 'Ciudad/municipio',
          onChanged: (_) => setState(() {}),
        ),
        _DeliveryField(
          controller: addressController,
          label: 'Dirección',
          onChanged: (_) => setState(() {}),
        ),
        _DeliveryField(
          controller: neighborhoodController,
          label: 'Barrio',
          onChanged: (_) => setState(() {}),
        ),
        _DeliveryField(
          controller: recipientController,
          label: 'Nombre de quien recibe',
          onChanged: (_) => setState(() {}),
        ),
        _DeliveryField(
          controller: directionsController,
          label: 'Referencia/indicaciones (opcional)',
          onChanged: (_) => setState(() {}),
        ),
      ],
    ],
  );

  Product? _productFor(String productId) {
    for (final candidate in widget.products) {
      if (candidate.id == productId) return candidate;
    }
    return null;
  }

  Future<void> _submit() async {
    if (submitting) return;
    setState(() {
      submitting = true;
      submissionError = null;
    });
    try {
      final order = await widget.onSubmit(
        requiresDelivery!,
        requiresDelivery == true
            ? DeliveryDetails(
                city: cityController.text,
                address: addressController.text,
                neighborhood: neighborhoodController.text,
                recipientName: recipientController.text,
                directions: directionsController.text.trim().isEmpty
                    ? null
                    : directionsController.text,
              )
            : null,
      );
      if (mounted) setState(() => createdOrder = order);
    } catch (error) {
      if (mounted) {
        setState(() => submissionError = _friendlyRequestError(error));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _spin() async {
    if (spinning) return;
    setState(() {
      spinning = true;
      spinningBenefit = null;
      submissionError = null;
    });
    try {
      final benefit = await widget.onSpin();
      if (!mounted) return;
      setState(() => spinningBenefit = benefit);
      await _wheelController.forward(from: 0);
      if (mounted) {
        setState(() {
          wheelBenefit = benefit;
          spinningBenefit = null;
        });
      }
    } catch (error) {
      if (mounted) {
        _wheelController.stop();
        setState(() {
          spinningBenefit = null;
          submissionError = _friendlyRequestError(error, wheel: true);
        });
      }
    } finally {
      if (mounted) setState(() => spinning = false);
    }
  }

  String _friendlyRequestError(Object error, {bool wheel = false}) {
    final value = error.toString().toLowerCase();
    if (value.contains('product_unavailable')) {
      return 'Uno de los productos ya no está disponible. '
          'Actualiza tu selección o pide asesoría.';
    }
    if (value.contains('delivery_')) {
      return 'Revisa la modalidad y los datos de entrega antes de continuar.';
    }
    return wheel
        ? 'No pudimos completar el giro en este momento. Puedes intentarlo nuevamente.'
        : 'No pudimos enviar tu solicitud en este momento. Inténtalo nuevamente.';
  }

  bool get _deliveryIsComplete =>
      requiresDelivery == false ||
      (requiresDelivery == true &&
          cityController.text.trim().isNotEmpty &&
          addressController.text.trim().isNotEmpty &&
          neighborhoodController.text.trim().isNotEmpty &&
          recipientController.text.trim().isNotEmpty);

  String get _deliveryLabel => requiresDelivery == true
      ? 'Envío a domicilio · costo por confirmar'
      : 'Acordar entrega con asesor';
}

class _FinalInfoCard extends StatelessWidget {
  const _FinalInfoCard({
    required this.icon,
    required this.title,
    required this.headline,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.green, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DeliveryField extends StatelessWidget {
  const _DeliveryField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _ReadyWheel extends StatelessWidget {
  const _ReadyWheel({required this.onSpin, required this.waiting});

  final VoidCallback? onSpin;
  final bool waiting;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('ready-wheel-panel'),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8EF),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE3C48E)),
    ),
    child: Column(
      children: [
        const Text(
          '¡Gira la ruleta y descubre tu beneficio!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.green,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        const Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: CustomPaint(
                key: Key('ready-wheel'),
                size: Size.square(175),
                painter: _WheelPainter(),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 42, color: Color(0xFF8D662F)),
          ],
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          key: const Key('wheel-spin-button'),
          onPressed: onSpin,
          icon: const Icon(Icons.casino_outlined),
          label: Text(waiting ? 'Verificando…' : 'Girar la ruleta'),
        ),
        if (!waiting) ...[
          const SizedBox(height: 5),
          const Text(
            '1 giro disponible',
            key: Key('wheel-spin-available'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    ),
  );
}

class _SpinningWheel extends StatelessWidget {
  const _SpinningWheel({required this.controller, required this.targetPercent});

  final AnimationController controller;
  final int targetPercent;

  double get _targetAngle {
    final index = switch (targetPercent) {
      5 => 0,
      10 => 1,
      15 => 2,
      _ => 0,
    };
    final alignment = (-math.pi / 3) - (index * 2 * math.pi / 3);
    return (6 * 2 * math.pi) + alignment;
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('spinning-wheel-panel'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3EC),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE3C48E)),
    ),
    child: Column(
      children: [
        const Text(
          '¡Girando ruleta...!',
          style: TextStyle(
            color: AppTheme.green,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Un momento, estamos descubriendo tu beneficio especial.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, child) => Transform.rotate(
                  angle:
                      CurvedAnimation(
                        parent: controller,
                        curve: Curves.easeOutCubic,
                      ).value *
                      _targetAngle,
                  child: child,
                ),
                child: const CustomPaint(
                  key: Key('spinning-wheel'),
                  size: Size.square(190),
                  painter: _WheelPainter(),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 42,
              color: Color(0xFF8D662F),
            ),
          ],
        ),
        const Text(
          'Amor y Amistad 2026',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter();

  static const labels = ['5%', '10%', '15%'];
  static const colors = [
    Color(0xFF2E6B50),
    Color(0xFFD3A955),
    Color(0xFFD98289),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweep = 2 * math.pi / 3;
    for (var index = 0; index < labels.length; index++) {
      final start = -math.pi / 2 + (index * sweep);
      canvas.drawArc(rect, start, sweep, true, Paint()..color = colors[index]);
      final labelAngle = start + sweep / 2;
      final painter = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter =
          center +
          Offset(math.cos(labelAngle), math.sin(labelAngle)) * (radius * .58);
      painter.paint(canvas, labelCenter - Offset(painter.width / 2, 13));
    }
    canvas.drawCircle(center, 18, Paint()..color = const Color(0xFFFFF3EC));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF8D662F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

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
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: valueColor == null ? null : FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SummaryProductCard extends StatelessWidget {
  const _SummaryProductCard({required this.item, required this.product});

  final OrderItemDraft item;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (item.itemType) {
      OrderItemType.primary => 'Producto principal',
      OrderItemType.other => 'Alternativa',
      OrderItemType.complementary => 'Complemento',
      OrderItemType.kit => 'Kit',
    };
    return Card(
      key: ValueKey('summary-product-${item.productId}'),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8DED0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 88,
                height: 108,
                child: product == null
                    ? const ColoredBox(
                        color: AppTheme.softBlue,
                        child: Icon(Icons.spa_outlined, color: AppTheme.blue),
                      )
                    : Image.asset(
                        product!.resolvedImagePath,
                        key: ValueKey('summary-image-${item.productId}'),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppTheme.softBlue,
                          child: Icon(Icons.spa_outlined, color: AppTheme.blue),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeLabel,
                    style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(product?.presentation ?? 'Presentación no especificada'),
                  Text('SKU: ${item.productCode} · Cantidad: ${item.quantity}'),
                  const SizedBox(height: 8),
                  Text(
                    _ProductCard.priceLabel(item.originalUnitPriceCop),
                    style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTotalsCard extends StatelessWidget {
  const _SummaryTotalsCard({
    required this.subtotalCop,
    required this.discountPercent,
    required this.discountCop,
    required this.netProductsCop,
  });

  final int subtotalCop;
  final int? discountPercent;
  final int discountCop;
  final int netProductsCop;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('summary-totals-card'),
    color: const Color(0xFFFFFBF4),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE3D5BF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Subtotal de productos',
            value: _ProductCard.priceLabel(subtotalCop),
          ),
          Container(
            key: const Key('summary-discount-row'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6EF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _SummaryRow(
              label: discountPercent == null
                  ? 'Descuento'
                  : 'Descuento Amor y Amistad ($discountPercent%)',
              value: discountCop == 0
                  ? r'$0 COP'
                  : '-${_ProductCard.priceLabel(discountCop)}',
              valueColor: AppTheme.green,
            ),
          ),
          _SummaryRow(
            label: 'Venta neta de productos',
            value: _ProductCard.priceLabel(netProductsCop),
          ),
          const Divider(height: 24),
          const _SummaryRow(label: 'Entrega/envío', value: 'Por confirmar'),
          const SizedBox(height: 8),
          Container(
            key: const Key('summary-total-row'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1DFC0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TOTAL A PAGAR',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _ProductCard.priceLabel(netProductsCop),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'El valor del envío se confirmará por separado.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
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
          prominent
              ? 'assets/images/welcome/portada_amor_amistad_2026.png'
              : 'assets/images/primera_pantalla.jpeg',
          alignment: Alignment.topCenter,
          fit: BoxFit.cover,
          opacity: AlwaysStoppedAnimation(prominent ? 1 : 0.14),
        ),
      ),
      if (prominent)
        Positioned(
          top: 178,
          left: 0,
          right: 0,
          height: 67,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE6FFF9F0), AppTheme.background],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Regala belleza, regala emociones',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
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
