class DynamicKeysHelper
  def labels
    t("analytics.actor.#{'admin_' if admin}name")  # mid-interpolation
    t("lti.calendar.#{lms_type}.title")            # mid-interpolation
    t("#{record.type}.type")                       # leading-interpolation
    t("trailing.prefix.#{suffix}")                 # trailing-interpolation
    t(:"sym.dynamic.#{seg}")                       # interpolated symbol
    t("plain.static.key")                          # static control
  end
end
