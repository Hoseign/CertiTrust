<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Issue Certificates - CertiTrust</title>
    <!-- Tailwind CSS -->
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    <!-- Alpine.js for Tab Toggle Interactivity -->
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
</head>
<body class="bg-gray-100 font-sans antialiased text-gray-900">

    <div class="max-w-3xl mx-auto py-12 px-4 sm:px-6 lg:px-8" x-data="{ mode: 'single' }">
        
        <!-- Page Header -->
        <div class="mb-8 text-center">
            <h1 class="text-3xl font-extrabold text-gray-800">CertiTrust Portal</h1>
            <p class="text-sm text-gray-600 mt-1">Issue official digital credentials as single entries or in batches.</p>
        </div>

        <div class="bg-white shadow-xl rounded-lg overflow-hidden">
            
            <!-- Tab Toggle / Mode Switcher Header -->
            <div class="flex border-b border-gray-200 bg-gray-50">
                <button @click="mode = 'single'" 
                        :class="mode === 'single' ? 'border-indigo-600 text-indigo-600 bg-white' : 'border-transparent text-gray-500 hover:text-gray-700'"
                        class="flex-1 py-4 px-6 text-center border-b-2 font-semibold text-sm transition focus:outline-none">
                    Single Mode
                </button>
                <button @click="mode = 'batch'" 
                        :class="mode === 'batch' ? 'border-indigo-600 text-indigo-600 bg-white' : 'border-transparent text-gray-500 hover:text-gray-700'"
                        class="flex-1 py-4 px-6 text-center border-b-2 font-semibold text-sm transition focus:outline-none">
                    Batch Mode (Multi-Student)
                </button>
            </div>

            <div class="p-6 sm:p-8">

                <!-- SINGLE MODE FORM -->
                <form x-show="mode === 'single'" action="{{ route('certificates.store') }}" method="POST" class="space-y-5" x-cloak>
                    @csrf
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Recipient Name</label>
                        <input type="text" name="recipient_name" required placeholder="e.g. Juan Dela Cruz" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2.5">
                    </div>

                    <div>
                        <label class="block text-sm font-medium text-gray-700">Course or Event</label>
                        <input type="text" name="course_or_event" required placeholder="e.g. Web Development Bootcamp" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2.5">
                    </div>

                    <div>
                        <label class="block text-sm font-medium text-gray-700">University Code</label>
                        <input type="text" name="university_code" required placeholder="e.g. UCU-IT-2026" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2.5">
                    </div>

                    <div>
                        <label class="block text-sm font-medium text-gray-700">Issue Date</label>
                        <input type="date" name="issue_date" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 border p-2.5">
                    </div>

                    <button type="submit" class="w-full bg-indigo-600 text-white py-3 px-4 rounded-md hover:bg-indigo-700 font-semibold shadow transition">
                        Issue Single Certificate
                    </button>
                </form>

                <!-- BATCH MODE FORM -->
                <form x-show="mode === 'batch'" action="{{ route('certificates.store') }}" method="POST" class="space-y-6" x-data="{ rows: [{ recipient_name: '', course_or_event: '', university_code: '', issue_date: '' }] }" x-cloak>
                    @csrf
                    <div class="space-y-4">
                        <template x-for="(row, index) in rows" :key="index">
                            <div class="p-4 border border-gray-200 rounded-lg bg-gray-50 space-y-3 relative shadow-sm">
                                <div class="flex justify-between items-center">
                                    <span class="text-xs font-bold uppercase tracking-wider text-indigo-600" x-text="'Certificate Entry #' + (index + 1)"></span>
                                    <button type="button" @click="rows.splice(index, 1)" x-show="rows.length > 1" class="text-red-500 hover:text-red-700 text-xs font-medium">Remove</button>
                                </div>

                                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                    <div>
                                        <label class="block text-xs font-medium text-gray-600">Recipient Name</label>
                                        <input type="text" :name="'certificates['+index+'][recipient_name]'" x-model="row.recipient_name" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm border p-2 text-sm">
                                    </div>
                                    <div>
                                        <label class="block text-xs font-medium text-gray-600">Course or Event</label>
                                        <input type="text" :name="'certificates['+index+'][course_or_event]'" x-model="row.course_or_event" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm border p-2 text-sm">
                                    </div>
                                    <div>
                                        <label class="block text-xs font-medium text-gray-600">University Code</label>
                                        <input type="text" :name="'certificates['+index+'][university_code]'" x-model="row.university_code" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm border p-2 text-sm">
                                    </div>
                                    <div>
                                        <label class="block text-xs font-medium text-gray-600">Issue Date</label>
                                        <input type="date" :name="'certificates['+index+'][issue_date]'" x-model="row.issue_date" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm border p-2 text-sm">
                                    </div>
                                </div>
                            </div>
                        </template>
                    </div>

                    <button type="button" @click="rows.push({ recipient_name: '', course_or_event: '', university_code: '', issue_date: '' })" class="w-full border-2 border-dashed border-gray-300 text-gray-600 py-2.5 rounded-lg text-sm font-semibold hover:border-indigo-500 hover:text-indigo-600 transition">
                        + Add Another Student Entry
                    </button>

                    <button type="submit" class="w-full bg-indigo-600 text-white py-3 px-4 rounded-md hover:bg-indigo-700 font-semibold shadow transition">
                        Issue Batch Certificates
                    </button>
                </form>

            </div>
        </div>
    </div>

</body>
</html>