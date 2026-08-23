String staffOperationErrorMessage(Object failure) {
  final value = failure.toString().toLowerCase();

  if (value.contains('availability_all_items_required')) {
    return 'Debes consultar en la tienda la disponibilidad de todos los productos.';
  }
  if (value.contains('availability_note_required')) {
    return 'Agrega una observación cuando la tienda reporte disponibilidad parcial o inexistente.';
  }
  if (value.contains('availability_verification_required') ||
      value.contains('customer_acceptance_availability_required')) {
    return 'Primero debes confirmar que todos los productos están disponibles para compra en la tienda.';
  }
  if (value.contains('shipping_confirmation_required') ||
      value.contains('customer_acceptance_shipping_required')) {
    return 'Primero debes definir el costo de envío, incluso cuando sea \$0.';
  }
  if (value.contains('current_customer_acceptance_required')) {
    return 'El cliente debe confirmar productos, cantidades, precio, envío y total vigente.';
  }
  if (value.contains('customer_acceptance_status_not_allowed')) {
    return 'La confirmación del cliente solo puede registrarse después de verificar disponibilidad en tienda.';
  }
  if (value.contains('customer_acceptance_note_required')) {
    return 'Describe brevemente cómo confirmó el cliente el pedido.';
  }
  if (value.contains('payments_feature_disabled')) {
    return 'Los pagos todavía no están habilitados. La compra a tienda permanece bloqueada.';
  }
  if (value.contains('invalid_order_transition')) {
    return 'El pedido cambió de estado. Actualiza la bandeja antes de continuar.';
  }
  if (value.contains('permission_denied') ||
      value.contains('access_denied') ||
      value.contains('row-level security')) {
    return 'Tu usuario no está autorizado para realizar esta operación.';
  }
  return 'No fue posible completar la operación. Actualiza el pedido e inténtalo nuevamente.';
}
