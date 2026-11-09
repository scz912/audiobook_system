<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Who the account is for. A 'caregiver' account manages child profiles and
   hands the phone over in Child Mode. An 'independent' account belongs to a
   teenager who uses the app on their own: one combined app, with a single
   child profile (themselves) behind it for listening history and settings. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('caregivers', function (Blueprint $table) {
            $table->string('account_type', 20)->default('caregiver')->after('name'); // caregiver | independent
        });
    }

    public function down(): void
    {
        Schema::table('caregivers', function (Blueprint $table) {
            $table->dropColumn('account_type');
        });
    }
};
