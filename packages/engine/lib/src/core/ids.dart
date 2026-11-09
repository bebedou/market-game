/// Typed identifiers. Each is a dense index into its list, assigned in order:
/// content IDs by position in the scenario file, state IDs by creation.
library;

extension type const MarketId(int index) {}

extension type const CategoryId(int index) {}

extension type const ProductId(int index) {}

extension type const SupplierId(int index) {}

extension type const PersonId(int index) {}

extension type const CompanyId(int index) {}

extension type const StoreId(int index) {}

extension type const SiteId(int index) {}

extension type const SegmentId(int index) {}

extension type const CohortId(int index) {}

extension type const StrategyId(int index) {}

extension type const BrandId(int index) {}

extension type const RegimeId(int index) {}

extension type const ResearchTierId(int index) {}

extension type const ManagerGradeId(int index) {}

extension type const DirectorGradeId(int index) {}

extension type const FormatId(int index) {}
