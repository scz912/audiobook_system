<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/* What the tips learn from (see TipLearner).

   tip_learning: for each kind of tip ("arm", e.g. reading_speed:down),
   how much it has been trusted so far, as a Beta(alpha, beta) belief, for
   one child (scope = child_id) and for everyone (scope = "global").

   tip_outcomes: each applied tip, with the child's listening before it,
   so a few sessions later we can tell whether it helped. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tip_learning', function (Blueprint $table) {
            $table->id();
            $table->string('scope', 36);
            $table->string('arm', 60);
            $table->double('alpha')->default(1);
            $table->double('beta')->default(1);
            $table->unsignedInteger('accepted')->default(0);
            $table->unsignedInteger('edited')->default(0);
            $table->unsignedInteger('dismissed')->default(0);
            $table->unsignedInteger('helped')->default(0);
            $table->unsignedInteger('not_helped')->default(0);
            $table->timestamps();

            $table->unique(['scope', 'arm']);
        });

        Schema::create('tip_outcomes', function (Blueprint $table) {
            $table->uuid('outcome_id')->primary();
            $table->foreignUuid('child_id')
                ->constrained('child_profiles', 'child_id')
                ->cascadeOnDelete();
            $table->string('arm', 60);
            $table->timestamp('applied_at');
            $table->json('baseline');
            $table->timestamp('evaluated_at')->nullable();
            // helped | no_change | worse | unknown
            $table->string('result', 20)->nullable();
            $table->double('change')->nullable();
            $table->timestamps();

            $table->index(['child_id', 'evaluated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tip_outcomes');
        Schema::dropIfExists('tip_learning');
    }
};
