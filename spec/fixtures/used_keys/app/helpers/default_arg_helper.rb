class DefaultArgHelper
  def labels
    t("with_string_default", default: "fallback")
    t("with_symbol_default", default: :other_key)
    t("with_hash_default", default: {one: "One", other: "Other"})
    t("with_dynamic_default", default: "prefix.#{suffix}")
    t("with_no_default")
  end
end
