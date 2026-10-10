user = User.find_by!(email: "dev.kurz@gmail.com")
user.update!(time_zone: "UTC")
user.mark_verified!
user.change_password!("e2e-Password-123")
user.forms.where(title: "Kurz E2E").destroy_all

form = Form.create!(user: user, title: "Kurz E2E")
days = %w[mon tue wed thu fri sat sun]
service = { "name" => "Haircut", "duration" => 60, "capacity" => 2, "days" => days, "times" => ["09:00", "10:00"] }
Forms::Definition.add(form, { "type" => "booking", "label" => "When", "services" => [service], "rules" => { "approval" => "auto" } })
Forms::Definition.add(form.reload, { "type" => "short_text", "label" => "Name", "required" => true })
Forms::Definition.add(form.reload, { "type" => "email", "label" => "Email", "required" => true })
Forms::Publish.call(form: form.reload)
form.reload

service_id = form.fields.find { |f| f["type"] == "booking" }["services"].first["id"]
tomorrow = Time.current.utc.beginning_of_day + 1.day

[["Ana Silva", tomorrow + 9.hours, "confirmed"], ["Bruno Costa", tomorrow + 9.hours, "pending"], ["Carla Dias", tomorrow + 10.hours, "confirmed"]].each do |name, at, status|
  slot = AppointmentSlot.find_or_create_by!(form: form, service_key: service_id, starts_at: at) { |row| row.capacity = 2 }
  slot.update!(booked: slot.booked + 1)
  Appointment.create!(
    form: form, response: FormResponse.create!(form: form, answers: {}), slot: slot, group_key: SecureRandom.uuid,
    status: status, client_name: name, client_email: "#{name.downcase.tr(' ', '.')}@example.com", snapshot: { "name" => "Haircut" },
  )
end
puts "seeded #{Appointment.where(form: form).count} appointments"
