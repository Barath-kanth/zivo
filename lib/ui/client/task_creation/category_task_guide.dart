import 'package:hyperlocal/data/models/task.dart';

/// Local UX suggestions, using existing task category identifiers.
abstract class CategoryTaskGuide {
  static const custom = 'Other — write my own task';
  static List<String> services(TaskCategory category) => switch (category) {
    TaskCategory.queueStanding => ["Queue at a government office", "Queue at a bank", "Queue for tickets", "Queue at a service centre"],
    TaskCategory.laundry => ["Wash and fold clothes", "Iron clothes", "Laundry pickup and return"],
    TaskCategory.groceryRun => ["Buy groceries", "Collect a grocery order", "Buy household essentials"],
    TaskCategory.homeCleaning => ["Regular home cleaning", "Deep clean a room", "Clean a kitchen", "Clean a bathroom"],
    TaskCategory.homeCooking => ["Prepare a family meal", "Meal preparation", "Help with food preparation"],
    TaskCategory.movingHelp => ["Move furniture", "Load or unload items", "Move boxes", "Rearrange a room"],
    TaskCategory.tutoring => ["School subject tutoring", "Language practice", "Computer skills lesson", "Exam revision support"],
    TaskCategory.techHelp => ["Set up a phone", "Set up a computer", "Resolve a Wi-Fi issue", "Install or configure software"],
    TaskCategory.petCare => ["Walk a dog", "Feed and check on a pet", "Pet sitting", "Accompany a pet appointment"],
    TaskCategory.tailoring => ["Shorten or hem clothing", "Repair a seam", "Adjust clothing fit", "Replace a zip or button"],
    TaskCategory.driver => ["Local driving assistance", "Airport driving assistance", "Drive for an appointment"],
    TaskCategory.errandRun => ["Collect a parcel", "Deliver an item", "Collect an order", "Run a local errand"],
    TaskCategory.gardening => ["Weed a garden", "Trim plants", "Water plants", "General garden maintenance"],
    TaskCategory.documentWork => ["Fill in a form", "Make photocopies", "Scan or organise documents"],
    TaskCategory.hospitalCompanion => ["Accompany a hospital visit", "Help with hospital registration", "Accompany a clinic appointment"],
    TaskCategory.babysitting => ["Babysit at home", "Supervise play or homework"],
    TaskCategory.elderCare => ["Provide companionship", "Accompany an appointment", "Help with daily activities"],
    TaskCategory.eventHelp => ["Set up an event", "Assist event guests", "Serve at an event", "Clean up after an event"],
    TaskCategory.photography => ["Photograph an event", "Take product photos", "Take portrait photos", "Photograph a property"],
    TaskCategory.homeRepair => ["Assemble furniture", "Repair a household fitting", "Help with minor plumbing", "Help with a small repair"],
    TaskCategory.phoneCheckIn => ["Check on an elder by phone", "Daily wellness call", "Remind someone about medicine"],
    TaskCategory.readingAloud => ["Read a letter aloud", "Read a form or notice", "Read a school message"],
    TaskCategory.remoteTutoring => ["Maths by phone", "Language practice by video", "Homework help by video"],
    TaskCategory.sightedAssist => ["60-second product check", "Read a label on camera", "Confirm a shopping item"],
    TaskCategory.other => ["General local assistance", "Help with a household task"],
  };

  static String detailsHint(TaskCategory category) => switch (category) {
    TaskCategory.queueStanding => "Tell the helper the venue, service, arrival time and any queue rules.",
    TaskCategory.laundry => "Describe the load, fabric care and whether washing supplies are available.",
    TaskCategory.groceryRun => "List the items, quantities, preferred shop and acceptable substitutions.",
    TaskCategory.homeCleaning => "Describe the rooms, approximate size, cleaning required and supplies available.",
    TaskCategory.homeCooking => "Include the number of people, menu, dietary needs and ingredients available.",
    TaskCategory.movingHelp => "Describe the items, sizes, stairs, access and whether transport is arranged.",
    TaskCategory.tutoring => "Include the subject, learner level, topic, lesson length and preferred format.",
    TaskCategory.techHelp => "Describe the device, issue and the result you need. Do not share passwords.",
    TaskCategory.petCare => "Include pet type, number, temperament, care instructions and timing.",
    TaskCategory.tailoring => "Describe the garment, quantity, fabric and alteration required.",
    TaskCategory.driver => "Include the pickup, destination, vehicle arrangement and timing.",
    TaskCategory.errandRun => "Include what to collect or deliver, pickup and drop-off details and timing.",
    TaskCategory.gardening => "Describe the garden area, plants, work needed and tools available.",
    TaskCategory.documentWork => "Describe the document, length, file format and work required.",
    TaskCategory.hospitalCompanion => "Include appointment time, meeting point, mobility and non-medical support needed.",
    TaskCategory.babysitting => "Include the number of children, age range, schedule and care instructions.",
    TaskCategory.elderCare => "Describe the non-medical assistance, mobility needs and schedule.",
    TaskCategory.eventHelp => "Describe the event, expected guests, duties and working hours.",
    TaskCategory.photography => "Describe the subject, location, number of images and delivery requirements.",
    TaskCategory.homeRepair => "Describe the fault or item, work needed and tools or parts available.",
    TaskCategory.phoneCheckIn => "Who to call, when, and what to ask. Share the phone number in chat after matching.",
    TaskCategory.readingAloud => "What to read (letter, form, message) and the language. Share a photo or text after matching.",
    TaskCategory.remoteTutoring => "Subject, learner level, and whether phone or video. No travel needed.",
    TaskCategory.sightedAssist => "What the blind neighbour needs checked, and how long (about 60 seconds).",
    TaskCategory.other => "Describe exactly what help you need, the expected result and timing.",
  };

  static List<Map<String, dynamic>> fallbackFields(TaskCategory category) {
    final fields = <Map<String, dynamic>>[
      ...switch (category) {
        TaskCategory.queueStanding => [{"id": "expected_wait_minutes", "label": "Expected wait time", "type": "number", "required": true, "unit": "min"}, {"id": "queue_setting", "label": "Queue setting", "type": "select", "required": true, "options": ["Indoors", "Outdoors", "Both"]}],
        TaskCategory.laundry => [{"id": "laundry_load", "label": "Load size", "type": "select", "required": true, "options": ["Small bag", "Medium bag", "Large bag", "Multiple bags"]}, {"id": "fabric_care", "label": "Fabric care", "type": "select", "required": true, "options": ["Everyday fabrics", "Delicate fabrics", "Mixed fabrics"]}],
        TaskCategory.groceryRun => [{"id": "stops_count", "label": "Number of shops", "type": "number", "required": true}, {"id": "travel_km", "label": "Approximate delivery distance", "type": "number", "required": true, "unit": "km"}],
        TaskCategory.homeCleaning => [{"id": "room_count", "label": "Number of rooms", "type": "number", "required": true}, {"id": "supplies_available", "label": "Cleaning supplies", "type": "select", "required": true, "options": ["Provided by me", "Helper should bring supplies"]}],
        TaskCategory.homeCooking => [{"id": "people_count", "label": "Number of people", "type": "number", "required": true}, {"id": "ingredients_available", "label": "Ingredients", "type": "select", "required": true, "options": ["Provided by me", "Shopping also required"]}],
        TaskCategory.movingHelp => [{"id": "item_count", "label": "Number of items", "type": "number", "required": true}, {"id": "flights_of_stairs", "label": "Flights of stairs", "type": "number", "required": true, "min": 0}, {"id": "helpers_needed", "label": "Helpers needed", "type": "number", "required": true}],
        TaskCategory.tutoring => [{"id": "learner_level", "label": "Learner level", "type": "select", "required": true, "options": ["Primary school", "Secondary school", "Advanced level", "Adult learner"]}, {"id": "lesson_hours", "label": "Lesson length", "type": "number", "required": true, "unit": "hours"}, {"id": "subject", "label": "Subject or topic", "type": "text", "required": true}],
        TaskCategory.techHelp => [{"id": "device_type", "label": "Device", "type": "select", "required": true, "options": ["Phone", "Tablet", "Laptop", "Desktop", "Router", "Printer", "Other device"]}, {"id": "device_count", "label": "Number of devices", "type": "number", "required": true}],
        TaskCategory.petCare => [{"id": "pet_type", "label": "Pet type", "type": "select", "required": true, "options": ["Dog", "Cat", "Bird", "Other pet"]}, {"id": "pet_count", "label": "Number of pets", "type": "number", "required": true}],
        TaskCategory.tailoring => [{"id": "garment_count", "label": "Number of garments", "type": "number", "required": true}, {"id": "garment_type", "label": "Garment type", "type": "select", "required": true, "options": ["Trousers", "Shirt", "Dress", "Skirt", "Other garment"]}],
        TaskCategory.driver => [{"id": "travel_km", "label": "Approximate journey distance", "type": "number", "required": true, "unit": "km"}, {"id": "transmission", "label": "Your vehicle transmission", "type": "select", "required": true, "options": ["Automatic", "Manual"]}],
        TaskCategory.errandRun => [{"id": "stops_count", "label": "Number of stops", "type": "number", "required": true}, {"id": "travel_km", "label": "Approximate travel distance", "type": "number", "required": true, "unit": "km"}],
        TaskCategory.gardening => [{"id": "garden_size", "label": "Garden size", "type": "select", "required": true, "options": ["Balcony or pots", "Small garden", "Medium garden", "Large garden"]}, {"id": "tools_available", "label": "Tools", "type": "select", "required": true, "options": ["Provided by me", "Helper should bring tools"]}],
        TaskCategory.documentWork => [{"id": "page_count", "label": "Number of pages", "type": "number", "required": true}, {"id": "file_format", "label": "File format", "type": "select", "required": true, "options": ["Word document", "PDF", "Spreadsheet", "Printed pages", "Other format"]}],
        TaskCategory.hospitalCompanion => [{"id": "mobility_support", "label": "Mobility support", "type": "select", "required": true, "options": ["Independent walking", "Walking assistance", "Wheelchair assistance"]}, {"id": "visit_hours", "label": "Expected visit length", "type": "number", "required": true, "unit": "hours"}],
        TaskCategory.babysitting => [{"id": "children_count", "label": "Number of children", "type": "number", "required": true}, {"id": "age_range", "label": "Age range", "type": "select", "required": true, "options": ["Under 2", "2–5 years", "6–12 years", "13–17 years", "Mixed ages"]}],
        TaskCategory.elderCare => [{"id": "support_type", "label": "Support needed", "type": "select", "required": true, "options": ["Companionship", "Mobility assistance", "Daily activities", "Appointment accompaniment"]}, {"id": "visit_hours", "label": "Expected visit length", "type": "number", "required": true, "unit": "hours"}],
        TaskCategory.eventHelp => [{"id": "guest_count", "label": "Approximate guests", "type": "number", "required": true}, {"id": "helpers_needed", "label": "Helpers needed", "type": "number", "required": true}],
        TaskCategory.photography => [{"id": "delivery_type", "label": "Photo delivery", "type": "select", "required": true, "options": ["Digital images", "Digital images and prints"]}, {"id": "editing_level", "label": "Editing", "type": "select", "required": true, "options": ["Basic colour correction", "Detailed retouching", "Unedited images"]}],
        TaskCategory.homeRepair => [{"id": "tools_available", "label": "Tools", "type": "select", "required": true, "options": ["Provided by me", "Helper should bring tools"]}, {"id": "parts_available", "label": "Parts or materials", "type": "select", "required": true, "options": ["Already available", "Need advice before purchasing", "Not required"]}],
        TaskCategory.phoneCheckIn => [{"id": "call_minutes", "label": "Call length", "type": "number", "required": true, "unit": "min"}],
        TaskCategory.readingAloud => [{"id": "pages_or_items", "label": "Pages or items to read", "type": "number", "required": true}],
        TaskCategory.remoteTutoring => [{"id": "lesson_hours", "label": "Lesson length", "type": "number", "required": true, "unit": "hours"}, {"id": "subject", "label": "Subject", "type": "text", "required": true}],
        TaskCategory.sightedAssist => [{"id": "call_minutes", "label": "Check length", "type": "number", "required": true, "unit": "min"}],
        TaskCategory.other => [{"id": "expected_hours", "label": "Expected time needed", "type": "number", "required": true, "unit": "hours"}],
      },
      {'id': 'deadline_at', 'label': 'Complete before', 'type': 'date', 'required': true},
    ];
    for (final field in fields) {
      if (field['type'] == 'number' && !field.containsKey('min')) {
        field['min'] = field['id'] == 'travel_km'
            ? 0
            : field['unit'] == 'hours' ? 0.25 : 1;
      }
    }
    return fields;
  }
}
