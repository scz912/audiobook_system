<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* Extra caregiver fields for the community. `is_community_member` gates the
   hub (only invited families get in); the rest are the public-ish profile. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('caregivers', function (Blueprint $table) {
            $table->boolean('is_community_member')->default(false)->after('is_active');
            $table->string('bio', 200)->nullable()->after('is_community_member');
            $table->string('avatar_emoji', 8)->default('🙂')->after('bio');
            $table->string('avatar_color', 9)->default('#DCE4FF')->after('avatar_emoji');
        });
    }

    public function down(): void
    {
        Schema::table('caregivers', function (Blueprint $table) {
            $table->dropColumn([
                'is_community_member',
                'bio',
                'avatar_emoji',
                'avatar_color',
            ]);
        });
    }
};
