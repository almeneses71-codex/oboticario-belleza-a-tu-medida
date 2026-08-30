import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models/staff_order.dart';
import '../domain/repositories/staff_repository.dart';
import '../domain/staff_operation_error.dart';

class StaffApp extends StatefulWidget {
  const StaffApp({required this.repository, super.key});

  final StaffRepository? repository;

  @override
  State<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends State<StaffApp> {
  late final StaffController controller;

  @override
  void initState() {
    super.initState();
    controller = StaffController(widget.repository)..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (_, _) =>
        FocusManager.instance.primaryFocus?.unfocus(),
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => controller.profile == null
          ? StaffLoginScreen(controller: controller)
          : StaffOrdersScreen(controller: controller),
    ),
  );
}

class StaffController extends ChangeNotifier {
  StaffController(this._repository);

  final StaffRepository? _repository;
  StaffProfile? profile;
  List<StaffOrder> orders = const [];
  StaffOrderFilter activeFilter = const StaffOrderFilter();
  int totalCount = 0;
  Map<String, int> statusCounts = const {};
  Map<String, int> attentionCounts = const {};
  List<StaffSellerOption> assignableSellers = const [];
  bool loading = true;
  bool submitting = false;
  String? error;

  bool get configured => _repository?.isConfigured == true;

  Future<void> initialize() async {
    if (!configured) {
      error = 'El entorno de pedidos no está configurado.';
      loading = false;
      notifyListeners();
      return;
    }
    try {
      if (_repository!.hasSession) {
        profile = await _repository.loadCurrentProfile();
        if (profile != null) {
          await _loadFirstPage();
          if (profile!.canViewAll) {
            assignableSellers = await _repository.loadAssignableSellers();
          }
        }
      }
    } catch (_) {
      await _repository!.signOut();
      profile = null;
      error = 'La sesión anterior no pudo validarse. Ingresa nuevamente.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    if (!configured || submitting) return;
    final repository = _repository!;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      profile = await repository.signIn(email: email, password: password);
      await _loadFirstPage();
      if (profile!.canViewAll) {
        assignableSellers = await repository.loadAssignableSellers();
      }
    } catch (failure) {
      debugPrint('No fue posible cargar el panel: $failure');
      final authenticated = repository.hasSession;
      profile = null;
      if (authenticated) await repository.signOut();
      error = authenticated
          ? 'El acceso fue aceptado, pero no fue posible cargar los pedidos.'
          : 'No fue posible ingresar. Revisa el correo y la contraseña.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _repository?.signOut();
    profile = null;
    orders = const [];
    totalCount = 0;
    statusCounts = const {};
    attentionCounts = const {};
    assignableSellers = const [];
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (profile == null || submitting) return;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      await _loadFirstPage(
        filter: activeFilter.copyWith(
          offset: 0,
          limit: orders.length > 25 ? orders.length : 25,
        ),
      );
    } catch (_) {
      error = 'No fue posible actualizar los pedidos.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> applyFilter(StaffOrderFilter filter) async {
    if (profile == null || submitting) return;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      await _loadFirstPage(filter: filter.copyWith(offset: 0, limit: 25));
    } catch (_) {
      error = 'No fue posible aplicar los filtros.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (profile == null || submitting || orders.length >= totalCount) return;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final page = await _repository!.loadOrders(
        filter: activeFilter.copyWith(offset: orders.length, limit: 25),
      );
      orders = [...orders, ...page.orders];
      totalCount = page.totalCount;
    } catch (_) {
      error = 'No fue posible cargar más pedidos.';
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> _loadFirstPage({
    StaffOrderFilter filter = const StaffOrderFilter(),
  }) async {
    activeFilter = filter;
    final page = await _repository!.loadOrders(filter: filter);
    orders = page.orders;
    totalCount = page.totalCount;
    statusCounts = await _repository.loadStatusCounts();
    attentionCounts = await _repository.loadAttentionCounts();
  }

  Future<void> advance(StaffOrder order) async {
    final next = order.nextStatus;
    if (next == null || submitting) return;
    await _runMutation(() => _repository!.updateStatus(order.id, next));
  }

  Future<void> confirmShipping(StaffOrder order, int amount) async {
    if (submitting) return;
    await _runMutation(() => _repository!.confirmShipping(order.id, amount));
  }

  Future<void> cancel(StaffOrder order, String reason) async {
    if (!order.canCancel || submitting || reason.trim().length < 5) return;
    await _runMutation(
      () =>
          _repository!.updateStatus(order.id, 'cancelled', note: reason.trim()),
    );
  }

  Future<void> assignResponsible(
    StaffOrder order,
    String sellerId,
    String reason,
  ) async {
    if (profile?.canViewAll != true || submitting || reason.trim().length < 5) {
      return;
    }
    await _runMutation(
      () => _repository!.assignOrder(order.id, sellerId, reason.trim()),
    );
  }

  Future<bool> createFollowup(
    StaffOrder order,
    String note,
    DateTime dueAt,
  ) async {
    if (submitting || note.trim().length < 5) return false;
    return _runMutation(
      () => _repository!.createFollowup(order.id, note.trim(), dueAt),
    );
  }

  Future<void> completeFollowup(
    StaffFollowup followup,
    String resultNote,
  ) async {
    if (submitting || !followup.isOpen || resultNote.trim().length < 5) return;
    await _runMutation(
      () => _repository!.completeFollowup(followup.id, resultNote.trim()),
    );
  }

  Future<bool> recordCustomerContact(StaffOrder order) async {
    if (submitting) return false;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      await _repository!.recordCustomerContact(order.id);
      await _loadFirstPage(
        filter: activeFilter.copyWith(
          offset: 0,
          limit: orders.length > 25 ? orders.length : 25,
        ),
      );
      return true;
    } catch (_) {
      error = 'No fue posible autorizar el contacto con este cliente.';
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> verifyAvailability(
    StaffOrder order,
    Map<String, String> itemResults,
    String? note,
  ) async {
    if (submitting || itemResults.length != order.items.length) return;
    await _runMutation(
      () => _repository!.verifyAvailability(order.id, itemResults, note),
    );
  }

  Future<void> recordCustomerAcceptance(
    StaffOrder order,
    String channel,
    String note,
  ) async {
    if (submitting || note.trim().length < 5) return;
    await _runMutation(
      () =>
          _repository!.recordCustomerAcceptance(order.id, channel, note.trim()),
    );
  }

  Future<bool> _runMutation(Future<void> Function() action) async {
    submitting = true;
    error = null;
    notifyListeners();
    try {
      await action();
      await _loadFirstPage(
        filter: activeFilter.copyWith(
          offset: 0,
          limit: orders.length > 25 ? orders.length : 25,
        ),
      );
      return true;
    } catch (failure) {
      error = staffOperationErrorMessage(failure);
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({required this.controller, super.key});

  final StaffController controller;

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Gestión de pedidos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Acceso exclusivo para el equipo comercial autorizado.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: obscurePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (widget.controller.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: widget.controller.submitting ? null : _submit,
                    icon: widget.controller.submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _submit() =>
      widget.controller.signIn(emailController.text, passwordController.text);
}

class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({required this.controller, super.key});

  final StaffController controller;

  @override
  State<StaffOrdersScreen> createState() => _StaffOrdersScreenState();
}

enum _OrderPeriod { all, today, sevenDays, thirtyDays }

class _StaffOrdersScreenState extends State<StaffOrdersScreen> {
  String search = '';
  String status = 'all';
  String seller = 'all';
  String attention = 'all';
  _OrderPeriod period = _OrderPeriod.all;
  Timer? searchDebounce;

  StaffController get controller => widget.controller;

  List<String> get sellers =>
      controller.assignableSellers
          .map((seller) => seller.displayName)
          .toList(growable: false)
        ..sort();

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void _applyFilters() {
    final now = DateTime.now().toUtc();
    final createdAfter = switch (period) {
      _OrderPeriod.all => null,
      _OrderPeriod.today => now.subtract(const Duration(hours: 24)),
      _OrderPeriod.sevenDays => now.subtract(const Duration(days: 7)),
      _OrderPeriod.thirtyDays => now.subtract(const Duration(days: 30)),
    };
    controller.applyFilter(
      StaffOrderFilter(
        search: search,
        status: status == 'all' ? null : status,
        sellerName: seller == 'all' ? null : seller,
        createdAfter: createdAfter,
        attention: attention == 'all' ? null : attention,
      ),
    );
  }

  void _searchChanged(String value) {
    setState(() => search = value);
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), _applyFilters);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pedidos'),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: controller.submitting ? null : controller.refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: controller.signOut,
          icon: const Icon(Icons.logout),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, ${controller.profile!.displayName}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    controller.profile!.canViewAll
                        ? '${_roleLabel(controller.profile!.role.name)} · puede consultar todos los pedidos.'
                        : 'Vendedor · solo puedes consultar tus pedidos asignados.',
                  ),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _OrderMetrics(counts: controller.statusCounts),
                  const SizedBox(height: 12),
                  _AttentionMetrics(
                    counts: controller.attentionCounts,
                    selected: attention,
                    onSelected: (value) {
                      setState(() => attention = value);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 16),
                  _filters(context),
                  const SizedBox(height: 20),
                  if (controller.orders.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          controller.activeFilter.search.isNotEmpty ||
                                  controller.activeFilter.status != null ||
                                  controller.activeFilter.sellerName != null ||
                                  controller.activeFilter.createdAfter !=
                                      null ||
                                  controller.activeFilter.attention != null
                              ? 'No hay pedidos que coincidan con los filtros.'
                              : 'No hay pedidos visibles para este usuario.',
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      '${controller.totalCount} pedido${controller.totalCount == 1 ? '' : 's'} encontrado${controller.totalCount == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 10),
                    ...controller.orders.map(
                      (order) => StaffOrderCard(
                        order: order,
                        busy: controller.submitting,
                        onAdvance: () => controller.advance(order),
                        onShipping: (amount) =>
                            controller.confirmShipping(order, amount),
                        onCancel: (reason) => controller.cancel(order, reason),
                        assignableSellers: controller.assignableSellers,
                        onAssign: (sellerId, reason) => controller
                            .assignResponsible(order, sellerId, reason),
                        onCreateFollowup: (note, dueAt) =>
                            controller.createFollowup(order, note, dueAt),
                        onCompleteFollowup: controller.completeFollowup,
                        onAuthorizeContact: () =>
                            controller.recordCustomerContact(order),
                        onVerifyAvailability: (results, note) =>
                            controller.verifyAvailability(order, results, note),
                        onRecordCustomerAcceptance: (channel, note) =>
                            controller.recordCustomerAcceptance(
                              order,
                              channel,
                              note,
                            ),
                      ),
                    ),
                    if (controller.orders.length < controller.totalCount) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: controller.submitting
                              ? null
                              : controller.loadMore,
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            'Cargar más (${controller.orders.length} de ${controller.totalCount})',
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _filters(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buscar y filtrar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Últimos dígitos, cliente o vendedor',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: _searchChanged,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'requested',
                      child: Text('Solicitado'),
                    ),
                    DropdownMenuItem(
                      value: 'contacted',
                      child: Text('Contactado'),
                    ),
                    DropdownMenuItem(
                      value: 'availability_verified',
                      child: Text('Disponibilidad verificada en tienda'),
                    ),
                    DropdownMenuItem(
                      value: 'confirmed',
                      child: Text('Confirmado'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelado'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => status = value ?? 'all');
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: attention,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Atención',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'contact_pending',
                      child: Text('Pendiente de contactar'),
                    ),
                    DropdownMenuItem(
                      value: 'availability_pending',
                      child: Text('Pendiente de consultar en tienda'),
                    ),
                    DropdownMenuItem(
                      value: 'delivery_pending',
                      child: Text('Entrega por definir'),
                    ),
                    DropdownMenuItem(
                      value: 'availability_issue',
                      child: Text('No disponible para compra en tienda'),
                    ),
                    DropdownMenuItem(
                      value: 'customer_acceptance',
                      child: Text('Pendiente de confirmación del cliente'),
                    ),
                    DropdownMenuItem(
                      value: 'overdue',
                      child: Text('Seguimiento vencido'),
                    ),
                    DropdownMenuItem(value: 'today', child: Text('Vence hoy')),
                    DropdownMenuItem(
                      value: 'upcoming',
                      child: Text('Próximos'),
                    ),
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Sin seguimiento'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => attention = value ?? 'all');
                    _applyFilters();
                  },
                ),
              ),
              if (controller.profile!.canViewAll && sellers.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: seller,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vendedor',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Todos'),
                      ),
                      ...sellers.map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => seller = value ?? 'all');
                      _applyFilters();
                    },
                  ),
                ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<_OrderPeriod>(
                  initialValue: period,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _OrderPeriod.all,
                      child: Text('Todo el periodo'),
                    ),
                    DropdownMenuItem(
                      value: _OrderPeriod.today,
                      child: Text('Últimas 24 horas'),
                    ),
                    DropdownMenuItem(
                      value: _OrderPeriod.sevenDays,
                      child: Text('Últimos 7 días'),
                    ),
                    DropdownMenuItem(
                      value: _OrderPeriod.thirtyDays,
                      child: Text('Últimos 30 días'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => period = value ?? _OrderPeriod.all);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _OrderMetrics extends StatelessWidget {
  const _OrderMetrics({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final requested = counts['requested'] ?? 0;
    final inProgress = const {
      'contacted',
      'availability_verified',
      'pending_payment',
      'payment_under_review',
      'preparing',
      'shipped',
    }.fold<int>(0, (total, status) => total + (counts[status] ?? 0));
    final confirmed = const {
      'confirmed',
      'paid',
      'delivered',
    }.fold<int>(0, (total, status) => total + (counts[status] ?? 0));
    final cancelled = counts['cancelled'] ?? 0;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Solicitados',
          value: requested,
          icon: Icons.inbox_outlined,
        ),
        _MetricCard(
          label: 'En gestión',
          value: inProgress,
          icon: Icons.pending_actions_outlined,
        ),
        _MetricCard(
          label: 'Confirmados',
          value: confirmed,
          icon: Icons.check_circle_outline,
        ),
        _MetricCard(
          label: 'Cancelados',
          value: cancelled,
          icon: Icons.cancel_outlined,
        ),
      ],
    );
  }
}

class _AttentionMetrics extends StatelessWidget {
  const _AttentionMetrics({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    children: [
      _chip(context, 'contact_pending', 'Por contactar', Icons.forum_outlined),
      _chip(
        context,
        'availability_pending',
        'Disponibilidad pendiente',
        Icons.storefront_outlined,
      ),
      _chip(
        context,
        'delivery_pending',
        'Entrega por definir',
        Icons.local_shipping_outlined,
      ),
      _chip(
        context,
        'availability_issue',
        'No disponibles en tienda',
        Icons.inventory_2_outlined,
      ),
      _chip(
        context,
        'customer_acceptance',
        'Pendientes del cliente',
        Icons.fact_check_outlined,
      ),
      _chip(context, 'overdue', 'Vencidos', Icons.warning_amber_rounded),
      _chip(context, 'today', 'Vencen hoy', Icons.today_outlined),
      _chip(context, 'upcoming', 'Próximos', Icons.schedule_outlined),
      _chip(context, 'none', 'Sin seguimiento', Icons.event_busy_outlined),
    ],
  );

  Widget _chip(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) => FilterChip(
    selected: selected == value,
    avatar: Icon(icon, size: 18),
    label: Text('$label: ${counts[value] ?? 0}'),
    onSelected: (_) => onSelected(selected == value ? 'all' : value),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class StaffOrderCard extends StatelessWidget {
  const StaffOrderCard({
    required this.order,
    required this.busy,
    required this.onAdvance,
    required this.onShipping,
    required this.onCancel,
    required this.assignableSellers,
    required this.onAssign,
    required this.onCreateFollowup,
    required this.onCompleteFollowup,
    required this.onAuthorizeContact,
    required this.onVerifyAvailability,
    required this.onRecordCustomerAcceptance,
    super.key,
  });

  final StaffOrder order;
  final bool busy;
  final VoidCallback onAdvance;
  final ValueChanged<int> onShipping;
  final ValueChanged<String> onCancel;
  final List<StaffSellerOption> assignableSellers;
  final void Function(String sellerId, String reason) onAssign;
  final Future<bool> Function(String note, DateTime dueAt) onCreateFollowup;
  final void Function(StaffFollowup followup, String resultNote)
  onCompleteFollowup;
  final Future<bool> Function() onAuthorizeContact;
  final void Function(Map<String, String> results, String? note)
  onVerifyAvailability;
  final void Function(String channel, String note) onRecordCustomerAcceptance;

  List<StaffSellerOption> get availableSellers => assignableSellers
      .where((seller) => seller.id != order.assignedSellerId)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey(order.id),
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Text(order.number, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_statusLabel(order.status)} · ${order.customerName}\n'
              '${order.assignedSellerName ?? 'Sin responsable'} · ${_dateTime(order.createdAt)} · ${_money(order.totalCop)}'
              '${_attentionSummary(order)}',
            ),
            const SizedBox(height: 8),
            if (order.isClosed)
              Text('Proceso cerrado: ${_statusLabel(order.status)}')
            else ...[
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: order.commercialProgress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Progreso ${order.completedCommercialSteps} de 5'),
                ],
              ),
              const SizedBox(height: 4),
              Text(_compactNextStep(order)),
            ],
          ],
        ),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(_statusLabel(order.status))),
                if (order.sellerName != null)
                  Chip(label: Text('Origen: ${order.sellerName!}')),
                if (order.assignedSellerName != null)
                  Chip(
                    label: Text('Responsable: ${order.assignedSellerName!}'),
                  ),
                if (order.hasAvailabilityIssue)
                  Chip(
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: const Text('No disponible para compra en tienda'),
                  ),
                if (order.needsCustomerAcceptance)
                  const Chip(
                    avatar: Icon(Icons.fact_check_outlined),
                    label: Text('Pendiente de confirmación del cliente'),
                  ),
                if (order.customerRequiresDelivery != null)
                  Chip(
                    avatar: Icon(
                      order.customerRequiresDelivery!
                          ? Icons.local_shipping_outlined
                          : Icons.handshake_outlined,
                    ),
                    label: Text(
                      order.customerRequiresDelivery!
                          ? 'Cliente solicita domicilio'
                          : 'Cliente prefiere entrega directa',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (order.nextAction != StaffOrderNextAction.none) ...[
              _NextActionCard(
                order: order,
                busy: busy,
                onAdvance: onAdvance,
                onVerifyAvailability: () => _askAvailability(context),
                onConfirmShipping: () => _askShipping(context),
                onRecordCustomerAcceptance: () =>
                    _askCustomerAcceptance(context),
              ),
              const SizedBox(height: 12),
            ],
            if (order.isClosed) ...[
              _ClosedOrderNotice(order: order),
              const SizedBox(height: 12),
            ],
            Text('${order.customerName} · ${order.customerWhatsapp}'),
            if (order.customerCity?.isNotEmpty == true)
              Text(order.customerCity!),
            if (order.customerRequiresDelivery != null) ...[
              const SizedBox(height: 6),
              Text(
                order.customerRequiresDelivery!
                    ? 'Preferencia del cliente: requiere domicilio.'
                    : 'Preferencia del cliente: entrega directa, sin domicilio.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (order.shippingStatus == 'pending_quote')
                const Text(
                  'Pendiente de validación por el equipo; todavía no define el costo ni confirma la entrega.',
                  style: TextStyle(color: Color(0xFF7A4E00)),
                ),
            ],
            if (order.channelName != null) Text('Canal: ${order.channelName}'),
            if (order.campaignName != null)
              Text('Campaña: ${order.campaignName}'),
            Text('Fecha Colombia: ${_dateTime(order.createdAt)}'),
            const Divider(height: 28),
            Text('Productos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...order.items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Chip(label: Text(_itemTypeLabel(item.type))),
                title: Text(item.name),
                subtitle: Text(
                  [
                    'SKU ${item.code} · ${item.quantity} × ${_money(item.unitPriceCop)}',
                    if (item.latestAvailability != null)
                      '${_availabilityLabel(item.latestAvailability!.result)} · '
                          '${item.latestAvailability!.actorName} · '
                          '${_dateTime(item.latestAvailability!.checkedAt)}',
                    if (item.latestAvailability?.note?.isNotEmpty == true)
                      item.latestAvailability!.note!,
                  ].join('\n'),
                ),
                trailing: Text(_money(item.subtotalCop)),
              ),
            ),
            const Divider(height: 28),
            Text('Subtotal: ${_money(order.subtotalCop)}'),
            Text('Descuento: ${_money(order.discountCop)}'),
            Text(switch (order.shippingStatus) {
              'not_required' => 'Entrega directa: sin costo de domicilio',
              'manually_confirmed' =>
                'Domicilio confirmado: ${_money(order.shippingCop)}',
              _ => 'Entrega: pendiente de definir',
            }),
            Text('Total: ${_money(order.totalCop)}'),
            if (order.deliveryHistory.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Historial de entrega',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...order.deliveryHistory.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    event.status == 'not_required'
                        ? Icons.handshake_outlined
                        : Icons.local_shipping_outlined,
                  ),
                  title: Text(
                    event.status == 'not_required'
                        ? 'Entrega directa · sin domicilio'
                        : 'Domicilio · ${_money(event.shippingCop)}',
                  ),
                  subtitle: Text(
                    '${event.actorName} (${_roleLabel(event.actorRole)}) · '
                    '${_dateTime(event.createdAt)}\n'
                    'Anterior: ${_deliveryEventLabel(event.previousStatus, event.previousCop)}',
                  ),
                ),
              ),
            ],
            if (order.customerAcceptances.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Confirmaciones del cliente',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...order.customerAcceptances.map(
                (acceptance) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    acceptance.acceptedTotalCop == order.totalCop
                        ? Icons.verified_outlined
                        : Icons.history_outlined,
                  ),
                  title: Text(
                    '${_acceptanceChannelLabel(acceptance.channel)} · '
                    '${_money(acceptance.acceptedTotalCop)}',
                  ),
                  subtitle: Text(
                    '${acceptance.actorName} (${_roleLabel(acceptance.actorRole)}) · '
                    '${_dateTime(acceptance.acceptedAt)}\n${acceptance.note}',
                  ),
                ),
              ),
            ],
            if (order.storePurchase != null) ...[
              const Divider(height: 28),
              Text(
                'Compra posterior a la tienda',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text(
                  _storePurchaseStatusLabel(order.storePurchase!.status),
                ),
                subtitle: Text(
                  'Registro independiente · creado ${_dateTime(order.storePurchase!.createdAt)}\n'
                  'La compra permanece bloqueada. El módulo de verificación de pagos todavía no está habilitado.',
                ),
              ),
            ],
            if (!order.isClosed) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: !busy && _validWhatsapp(order.customerWhatsapp)
                    ? () => _contactCustomer(order)
                    : null,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Contactar cliente por WhatsApp'),
              ),
            ],
            if (order.contactHistory.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Historial de contacto',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...order.contactHistory.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Apertura de WhatsApp'),
                  subtitle: Text(
                    '${event.actorName} (${_roleLabel(event.actorRole)}) · '
                    '${_dateTime(event.createdAt)}',
                  ),
                ),
              ),
            ],
            if (!order.isClosed) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _askFollowup(context),
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Programar seguimiento'),
              ),
            ],
            if (order.followups.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Seguimiento operativo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...order.followups.map(
                (followup) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    followup.isOpen
                        ? followup.isOverdue
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_outlined
                        : Icons.task_alt,
                    color: followup.isOverdue
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  title: Text(followup.note),
                  subtitle: Text(
                    [
                      '${followup.isOpen ? 'Pendiente' : 'Completado'} · ${_dateTime(followup.dueAt)}',
                      if (followup.creatorName != null)
                        'Creado por ${followup.creatorName} (${_roleLabel(followup.creatorRole)})',
                      if (followup.completedByName != null)
                        'Completado por ${followup.completedByName}',
                      if (followup.completionNote != null)
                        followup.completionNote!,
                    ].join('\n'),
                  ),
                  trailing: followup.isOpen && !order.isClosed
                      ? TextButton(
                          onPressed: busy
                              ? null
                              : () => _askCompleteFollowup(context, followup),
                          child: const Text('Finalizar seguimiento'),
                        )
                      : null,
                ),
              ),
            ],
            if (!order.isClosed && availableSellers.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _askAssignment(context),
                icon: const Icon(Icons.assignment_ind_outlined),
                label: const Text('Cambiar responsable'),
              ),
            ],
            if (order.assignmentHistory.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Historial de responsables',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...order.assignmentHistory.map(
                (event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    event.previousSellerName == null
                        ? 'Asignado a ${event.newSellerName}'
                        : '${event.previousSellerName} → ${event.newSellerName}',
                  ),
                  subtitle: Text(
                    [
                      _dateTime(event.createdAt),
                      if (event.actorName != null)
                        '${event.actorName} (${_roleLabel(event.actorRole)})',
                      event.reason,
                    ].join('\n'),
                  ),
                ),
              ),
            ],
            const Divider(height: 28),
            Text(
              'Línea de tiempo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._operationalTimeline(order).map(
              (activity) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(activity.icon, size: 20),
                title: Text(activity.title),
                subtitle: Text(
                  [
                    _dateTime(activity.createdAt),
                    if (activity.actorName != null)
                      '${activity.actorName} (${_roleLabel(activity.actorRole)})',
                    if (activity.detail?.isNotEmpty == true) activity.detail!,
                  ].join('\n'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (order.canCancel)
                  TextButton.icon(
                    onPressed: busy ? null : () => _askCancellation(context),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar pedido'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _askShipping(BuildContext context) async {
    bool? requiresDelivery;
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, input) => StatefulBuilder(
          builder: (context, setDialogState) {
            final parsed = int.tryParse(
              input.text.replaceAll(RegExp(r'\D'), ''),
            );
            final canSave =
                requiresDelivery == false ||
                (requiresDelivery == true &&
                    parsed != null &&
                    parsed > 0 &&
                    parsed <= 100000);
            return AlertDialog(
              title: const Text('Definir entrega del pedido'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('¿Este pedido requiere domicilio?'),
                    ),
                    ListTile(
                      leading: Icon(
                        requiresDelivery == false
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: const Text('Entrega directa (sin domicilio)'),
                      subtitle: const Text(
                        'El producto se entrega directamente al cliente.',
                      ),
                      selected: requiresDelivery == false,
                      onTap: () =>
                          setDialogState(() => requiresDelivery = false),
                    ),
                    ListTile(
                      leading: Icon(
                        requiresDelivery == true
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: const Text('Requiere domicilio'),
                      subtitle: const Text(
                        'El costo se suma por separado al total.',
                      ),
                      selected: requiresDelivery == true,
                      onTap: () =>
                          setDialogState(() => requiresDelivery = true),
                    ),
                    if (requiresDelivery == true)
                      TextField(
                        controller: input,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Costo del domicilio en pesos',
                          helperText: 'Ingresa un valor entre 1 y 100.000.',
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => _closeDialog(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () => _closeDialog(
                          dialogContext,
                          requiresDelivery == true ? parsed : 0,
                        )
                      : null,
                  child: const Text('Guardar entrega'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (amount != null) onShipping(amount);
  }

  Future<void> _askAvailability(BuildContext context) async {
    final results = <String, String?>{
      for (final item in order.items) item.id: item.latestAvailability?.result,
    };
    final request = await showDialog<_AvailabilityRequest>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, noteController) => StatefulBuilder(
          builder: (context, setDialogState) {
            final complete = results.values.every((value) => value != null);
            final needsNote = results.values.any(
              (value) => value != null && value != 'available',
            );
            final noteValid =
                !needsNote || noteController.text.trim().length >= 5;
            return AlertDialog(
              title: const Text('Consultar disponibilidad en tienda'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in order.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.name} · ${item.quantity} unidad(es)',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: results[item.id],
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Disponibilidad',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'available',
                                    child: Text('Disponible'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'partial',
                                    child: Text(
                                      'Disponible parcialmente en tienda',
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'unavailable',
                                    child: Text('No disponible'),
                                  ),
                                ],
                                onChanged: (value) => setDialogState(
                                  () => results[item.id] = value,
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: noteController,
                        onChanged: (_) => setDialogState(() {}),
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Observación',
                          helperText:
                              'Obligatoria cuando un producto no está completamente disponible.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => _closeDialog(dialogContext),
                  child: const Text('Volver'),
                ),
                FilledButton(
                  onPressed: complete && noteValid
                      ? () => _closeDialog(
                          dialogContext,
                          _AvailabilityRequest(
                            results.map((key, value) => MapEntry(key, value!)),
                            noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                          ),
                        )
                      : null,
                  child: const Text('Guardar verificación'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (request != null) onVerifyAvailability(request.results, request.note);
  }

  Future<void> _askCustomerAcceptance(BuildContext context) async {
    var channel = 'whatsapp';
    final request = await showDialog<_CustomerAcceptanceRequest>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, noteController) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('Registrar confirmación del cliente'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'El cliente debe haber aceptado productos, cantidades, precio, envío y total ${_money(order.totalCop)}.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: channel,
                    decoration: const InputDecoration(
                      labelText: 'Canal de confirmación',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'whatsapp',
                        child: Text('WhatsApp'),
                      ),
                      DropdownMenuItem(value: 'phone', child: Text('Llamada')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => channel = value ?? 'whatsapp'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    onChanged: (_) => setDialogState(() {}),
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Observación',
                      hintText:
                          'Ejemplo: cliente acepta productos, envío y total.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _closeDialog(dialogContext),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: noteController.text.trim().length >= 5
                    ? () => _closeDialog(
                        dialogContext,
                        _CustomerAcceptanceRequest(
                          channel,
                          noteController.text.trim(),
                        ),
                      )
                    : null,
                child: const Text('Guardar confirmación'),
              ),
            ],
          ),
        ),
      ),
    );
    if (request != null) {
      onRecordCustomerAcceptance(request.channel, request.note);
    }
  }

  Future<void> _askAssignment(BuildContext context) async {
    var selectedSellerId = availableSellers.first.id;
    final request = await showDialog<_AssignmentRequest>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, reasonController) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Cambiar responsable'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedSellerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo responsable',
                    border: OutlineInputBorder(),
                  ),
                  items: availableSellers
                      .map(
                        (seller) => DropdownMenuItem(
                          value: seller.id,
                          child: Text('${seller.displayName} (${seller.code})'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedSellerId = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Motivo obligatorio',
                    hintText: 'Ejemplo: redistribución de carga operativa',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => _closeDialog(dialogContext),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () {
                  final reason = reasonController.text.trim();
                  if (reason.length >= 5) {
                    _closeDialog(
                      dialogContext,
                      _AssignmentRequest(selectedSellerId, reason),
                    );
                  }
                },
                child: const Text('Guardar asignación'),
              ),
            ],
          ),
        ),
      ),
    );
    if (request != null) onAssign(request.sellerId, request.reason);
  }

  Future<void> _askCancellation(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, input) => AlertDialog(
          title: const Text('Cancelar pedido'),
          content: TextField(
            controller: input,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Motivo obligatorio',
              hintText: 'Ejemplo: la tienda reportó el producto agotado',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _closeDialog(dialogContext),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                final value = input.text.trim();
                if (value.length >= 5) _closeDialog(dialogContext, value);
              },
              child: const Text('Confirmar cancelación'),
            ),
          ],
        ),
      ),
    );
    if (reason != null) onCancel(reason);
  }

  Future<void> _askFollowup(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _ProgramFollowupDialog(onSubmit: onCreateFollowup),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seguimiento programado correctamente')),
      );
    }
  }

  Future<void> _askCompleteFollowup(
    BuildContext context,
    StaffFollowup followup,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DialogTextControllerHost(
        builder: (context, input) => AlertDialog(
          title: const Text('Registrar resultado del seguimiento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tarea: ${followup.note}'),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '¿Qué resultado tuvo la gestión?',
                  hintText: 'Ejemplo: cliente confirmó que desea continuar.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta acción solo cierra esta tarea interna. No confirma, entrega ni completa el pedido.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _closeDialog(dialogContext),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                final value = input.text.trim();
                if (value.length >= 5) _closeDialog(dialogContext, value);
              },
              child: const Text('Finalizar esta tarea'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onCompleteFollowup(followup, result);
  }

  Future<void> _contactCustomer(StaffOrder order) async {
    final authorized = await onAuthorizeContact();
    if (!authorized) return;
    final uri = Uri.https('wa.me', '/${order.customerWhatsapp}', {
      'text': 'Hola. Te contactamos sobre tu solicitud ${order.number}.',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ClosedOrderNotice extends StatelessWidget {
  const _ClosedOrderNotice({required this.order});

  final StaffOrder order;

  @override
  Widget build(BuildContext context) {
    final event = order.closingEvent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pedido ${_statusLabel(order.status).toLowerCase()}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Motivo: ${event?.note ?? 'No hay un motivo registrado.'}'),
          if (event != null) ...[
            const SizedBox(height: 4),
            Text(
              '${event.actorName ?? 'Sistema'} (${_roleLabel(event.actorRole)}) · '
              '${_dateTime(event.createdAt)}',
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'El proceso está cerrado y no admite nuevas acciones comerciales.',
          ),
        ],
      ),
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({
    required this.order,
    required this.busy,
    required this.onAdvance,
    required this.onVerifyAvailability,
    required this.onConfirmShipping,
    required this.onRecordCustomerAcceptance,
  });

  final StaffOrder order;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onVerifyAvailability;
  final VoidCallback onConfirmShipping;
  final VoidCallback onRecordCustomerAcceptance;

  @override
  Widget build(BuildContext context) {
    final action = order.nextAction;
    final (description, label, icon, callback) = switch (action) {
      StaffOrderNextAction.markContacted => (
        'Contacta al cliente y registra que la conversación comenzó.',
        'Marcar contactado',
        Icons.forum_outlined,
        onAdvance,
      ),
      StaffOrderNextAction.verifyAvailability => (
        order.hasAvailabilityIssue
            ? 'Hay productos no disponibles o por confirmar. Consulta nuevamente su compra en la tienda.'
            : 'Verifica en la tienda si cada producto puede comprarse para este pedido.',
        'Consultar disponibilidad en tienda',
        Icons.storefront_outlined,
        onVerifyAvailability,
      ),
      StaffOrderNextAction.markAvailabilityVerified => (
        'Todos los productos aparecen disponibles. Registra el resultado en el estado del pedido.',
        'Disponibilidad verificada en tienda',
        Icons.verified_outlined,
        onAdvance,
      ),
      StaffOrderNextAction.confirmShipping => (
        'Indica si el pedido requiere domicilio o se entregará directamente al cliente.',
        'Definir entrega',
        Icons.local_shipping_outlined,
        onConfirmShipping,
      ),
      StaffOrderNextAction.recordCustomerAcceptance => (
        'El cliente debe aceptar productos, cantidades, precio, envío y total vigente.',
        'Registrar confirmación del cliente',
        Icons.fact_check_outlined,
        onRecordCustomerAcceptance,
      ),
      StaffOrderNextAction.confirmOrder => (
        'La disponibilidad, el envío y la aceptación están completos. Ya puedes confirmar el pedido.',
        'Confirmar pedido',
        Icons.check_circle_outline,
        onAdvance,
      ),
      StaffOrderNextAction.none => ('', '', Icons.info_outline, onAdvance),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Siguiente paso',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(description),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : callback,
            icon: Icon(icon),
            label: Text(label),
          ),
        ],
      ),
    );
  }
}

class _AssignmentRequest {
  const _AssignmentRequest(this.sellerId, this.reason);
  final String sellerId;
  final String reason;
}

void _closeDialog<T>(BuildContext context, [T? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).pop(result);
}

class _DialogTextControllerHost extends StatefulWidget {
  const _DialogTextControllerHost({required this.builder});

  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<_DialogTextControllerHost> createState() =>
      _DialogTextControllerHostState();
}

class _DialogTextControllerHostState extends State<_DialogTextControllerHost> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, controller);
}

class _ProgramFollowupDialog extends StatefulWidget {
  const _ProgramFollowupDialog({required this.onSubmit});

  final Future<bool> Function(String note, DateTime dueAt) onSubmit;

  @override
  State<_ProgramFollowupDialog> createState() => _ProgramFollowupDialogState();
}

class _ProgramFollowupDialogState extends State<_ProgramFollowupDialog> {
  final noteController = TextEditingController();
  DateTime dueAt = DateTime.now().add(const Duration(days: 1));
  bool saving = false;
  String? error;

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (saving) return;
    final note = noteController.text.trim();
    if (note.length < 5) {
      setState(
        () => error = 'Describe la próxima gestión en al menos 5 caracteres.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final saved = await widget.onSubmit(note, dueAt);
    if (!mounted) return;
    if (saved) {
      _closeDialog(context, true);
      return;
    }
    setState(() {
      saving = false;
      error = 'No fue posible programar el seguimiento. Inténtalo nuevamente.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Programar seguimiento'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: noteController,
          enabled: !saving,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          onChanged: (_) {
            if (error != null) setState(() => error = null);
          },
          decoration: const InputDecoration(
            labelText: 'Próxima gestión',
            hintText: 'Ejemplo: volver a consultar disponibilidad en la tienda',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: 1,
          decoration: const InputDecoration(
            labelText: 'Plazo',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Hoy')),
            DropdownMenuItem(value: 1, child: Text('Mañana')),
            DropdownMenuItem(value: 3, child: Text('En 3 días')),
            DropdownMenuItem(value: 7, child: Text('En 7 días')),
          ],
          onChanged: saving
              ? null
              : (days) {
                  if (days != null) {
                    setState(
                      () => dueAt = DateTime.now().add(
                        Duration(days: days, hours: 1),
                      ),
                    );
                  }
                },
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => _closeDialog(context),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: saving ? null : _submit,
        child: saving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Programar'),
      ),
    ],
  );
}

class _AvailabilityRequest {
  const _AvailabilityRequest(this.results, this.note);
  final Map<String, String> results;
  final String? note;
}

class _CustomerAcceptanceRequest {
  const _CustomerAcceptanceRequest(this.channel, this.note);
  final String channel;
  final String note;
}

String _attentionSummary(StaffOrder order) {
  if (order.hasAvailabilityIssue) {
    final affected = order.items
        .where((item) => item.hasAvailabilityIssue)
        .map((item) => item.name)
        .join(', ');
    return '\n⚠ No disponible para compra en tienda: $affected';
  }
  if (order.needsCustomerAcceptance) {
    return '\n⚠ Esperando confirmación del cliente';
  }
  final open = order.followups.where((item) => item.isOpen).toList();
  if (open.isEmpty) return '';
  if (open.any((item) => item.isOverdue)) return '\n⚠ Seguimiento vencido';
  open.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return '\nPróximo seguimiento: ${_dateTime(open.first.dueAt)}';
}

String _availabilityLabel(String result) => switch (result) {
  'available' => 'Disponible',
  'partial' => 'Disponible parcialmente en tienda',
  'unavailable' => 'No disponible en tienda',
  _ => result,
};

String _storePurchaseStatusLabel(String status) => switch (status) {
  'awaiting_payment_verification' => 'Pendiente de verificación de pago',
  'ready_to_purchase' => 'Autorizada para comprar en tienda',
  'purchased' => 'Comprada en tienda',
  'cancelled' => 'Compra cancelada',
  _ => status,
};

String _acceptanceChannelLabel(String channel) => switch (channel) {
  'whatsapp' => 'WhatsApp',
  'phone' => 'Llamada',
  _ => channel,
};

bool _validWhatsapp(String value) => RegExp(r'^\d{10,15}$').hasMatch(value);

String _dateTime(DateTime value) {
  final colombia = value.toUtc().subtract(const Duration(hours: 5));
  return '${colombia.day.toString().padLeft(2, '0')}/${colombia.month.toString().padLeft(2, '0')}/${colombia.year} '
      '${colombia.hour.toString().padLeft(2, '0')}:${colombia.minute.toString().padLeft(2, '0')}';
}

String _itemTypeLabel(String type) => switch (type) {
  'primary' => 'Principal',
  'complementary' => 'Complemento',
  'kit' => 'Kit',
  'other' => 'Otro producto',
  _ => type.replaceAll('_', ' '),
};

String _roleLabel(String? role) => switch (role) {
  'admin' => 'Administrador',
  'owner' => 'Propietario',
  'manager' => 'Supervisor',
  'seller' => 'Vendedor',
  _ => 'Sistema',
};

String _money(int value) {
  final digits = value.toString();
  final result = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) result.write('.');
    result.write(digits[index]);
  }
  return '\$${result.toString()} COP';
}

String _statusLabel(String status) => switch (status) {
  'requested' => 'Solicitado',
  'contacted' => 'Contactado',
  'availability_verified' => 'Disponibilidad verificada en tienda',
  'confirmed' => 'Confirmado',
  'cancelled' => 'Cancelado',
  'returned' => 'Devuelto',
  'refunded' => 'Reembolsado',
  _ => status.replaceAll('_', ' '),
};

String _compactNextStep(StaffOrder order) => switch (order.nextAction) {
  StaffOrderNextAction.markContacted => 'Pendiente: contactar al cliente',
  StaffOrderNextAction.verifyAvailability =>
    'Pendiente: consultar disponibilidad en tienda',
  StaffOrderNextAction.markAvailabilityVerified =>
    'Pendiente: registrar disponibilidad verificada',
  StaffOrderNextAction.confirmShipping => 'Pendiente: definir la entrega',
  StaffOrderNextAction.recordCustomerAcceptance =>
    'Pendiente: confirmación del cliente',
  StaffOrderNextAction.confirmOrder => 'Pendiente: confirmar el pedido',
  StaffOrderNextAction.none when order.isConfirmed => 'Pedido confirmado',
  StaffOrderNextAction.none => 'Sin acciones comerciales pendientes',
};

String _deliveryEventLabel(String status, int amount) => switch (status) {
  'pending_quote' => 'entrega sin definir',
  'not_required' => 'entrega directa sin domicilio',
  _ => 'domicilio de ${_money(amount)}',
};

class _OrderActivity {
  const _OrderActivity({
    required this.title,
    required this.createdAt,
    required this.icon,
    this.actorName,
    this.actorRole,
    this.detail,
  });

  final String title;
  final DateTime createdAt;
  final IconData icon;
  final String? actorName;
  final String? actorRole;
  final String? detail;
}

List<_OrderActivity> _operationalTimeline(StaffOrder order) {
  final activities = <_OrderActivity>[
    for (final event in order.history)
      _OrderActivity(
        title: event.previousStatus == null
            ? _statusLabel(event.status)
            : '${_statusLabel(event.previousStatus!)} → ${_statusLabel(event.status)}',
        createdAt: event.createdAt,
        icon: Icons.swap_horiz,
        actorName: event.actorName,
        actorRole: event.actorRole,
        detail: event.note,
      ),
    for (final item in order.items)
      for (final check in item.availabilityHistory)
        _OrderActivity(
          title: 'Disponibilidad: ${item.name}',
          createdAt: check.checkedAt,
          icon: Icons.storefront_outlined,
          actorName: check.actorName,
          actorRole: check.actorRole,
          detail: [
            _availabilityLabel(check.result),
            if (check.note?.isNotEmpty == true) check.note!,
          ].join(' · '),
        ),
    for (final event in order.deliveryHistory)
      _OrderActivity(
        title: event.status == 'not_required'
            ? 'Entrega definida: directa sin domicilio'
            : 'Entrega definida: domicilio',
        createdAt: event.createdAt,
        icon: event.status == 'not_required'
            ? Icons.handshake_outlined
            : Icons.local_shipping_outlined,
        actorName: event.actorName,
        actorRole: event.actorRole,
        detail: event.status == 'not_required'
            ? 'Sin costo de domicilio'
            : _money(event.shippingCop),
      ),
    for (final acceptance in order.customerAcceptances)
      _OrderActivity(
        title: 'Confirmación del cliente',
        createdAt: acceptance.acceptedAt,
        icon: Icons.fact_check_outlined,
        actorName: acceptance.actorName,
        actorRole: acceptance.actorRole,
        detail:
            '${_acceptanceChannelLabel(acceptance.channel)} · ${_money(acceptance.acceptedTotalCop)} · ${acceptance.note}',
      ),
    for (final event in order.contactHistory)
      _OrderActivity(
        title: 'Contacto por WhatsApp',
        createdAt: event.createdAt,
        icon: Icons.chat_outlined,
        actorName: event.actorName,
        actorRole: event.actorRole,
      ),
    for (final event in order.assignmentHistory)
      _OrderActivity(
        title: event.previousSellerName == null
            ? 'Responsable asignado: ${event.newSellerName}'
            : 'Responsable: ${event.previousSellerName} → ${event.newSellerName}',
        createdAt: event.createdAt,
        icon: Icons.person_outline,
        actorName: event.actorName,
        actorRole: event.actorRole,
        detail: event.reason,
      ),
    for (final followup in order.followups) ...[
      _OrderActivity(
        title: 'Seguimiento programado',
        createdAt: followup.createdAt,
        icon: Icons.add_task_outlined,
        actorName: followup.creatorName,
        actorRole: followup.creatorRole,
        detail: '${followup.note} · vence ${_dateTime(followup.dueAt)}',
      ),
      if (followup.completedAt != null)
        _OrderActivity(
          title: 'Seguimiento completado',
          createdAt: followup.completedAt!,
          icon: Icons.task_alt,
          actorName: followup.completedByName,
          detail: followup.completionNote,
        ),
    ],
    if (order.storePurchase != null)
      _OrderActivity(
        title: 'Compra posterior a la tienda creada',
        createdAt: order.storePurchase!.createdAt,
        icon: Icons.shopping_bag_outlined,
        detail: _storePurchaseStatusLabel(order.storePurchase!.status),
      ),
  ];
  activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return activities;
}
