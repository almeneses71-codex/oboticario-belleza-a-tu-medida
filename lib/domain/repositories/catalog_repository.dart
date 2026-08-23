import '../models/product.dart';
import '../models/question.dart';

abstract interface class CatalogRepository {
  Future<List<Product>> loadProducts();
  Future<List<Question>> loadQuestions();
}
